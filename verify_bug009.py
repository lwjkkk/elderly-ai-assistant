# BUG-009 复现验证：AI从对话自动提取健康数据(对话摘要落库+同步)是否生效
# mock get_agent_answer 和摘要LLM，走真实 chat 接口 + 鉴权 + 落库 + sync
import random
import threading

from fastapi.testclient import TestClient

from db.database import init_db, get_db
from db.models import User, ChatSummary
from main import app
import core.agent
import core.chat_summary

init_db()
client = TestClient(app)

# 记录是否被落库
inserted = threading.Event()


def fake_agent(q):
    # 症状类问题 → 返回 health 模块 + 症状建议
    return {"answer": "建议您监测血压并注意休息，如持续头晕请及时就医。", "module": "health"}


def fake_qwen(prompt, user):
    # 摘要提炼成功
    return "SUMMARY: 用户近两日头晕，建议监测血压，症状持续需及时就医"


core.agent.get_agent_answer = fake_agent
core.chat_summary.call_qwen = fake_qwen


def main():
    ep = f"13{random.randint(0, 999999999):09d}"
    assert client.post("/api/auth/register", json={"phone": ep, "password": "123456", "nickname": "张奶奶", "role": "elder"}).status_code == 201
    tok = client.post("/api/auth/login", json={"phone": ep, "password": "123456"}).json()["access_token"]
    h = {"Authorization": f"Bearer {tok}"}
    db = next(get_db()); eid = db.query(User).filter(User.phone == ep).first().id; db.close()

    # 场景1：老人登录 + 症状类问题 → 应落库
    r = client.post("/api/chat", json={"question": "我这两天头晕"}, headers=h)
    print("[chat带token症状问题]", r.status_code, r.json().get("module"))
    assert r.status_code == 200
    # 后台线程落库，稍等
    for _ in range(30):
        db = next(get_db()); n = db.query(ChatSummary).filter(ChatSummary.elder_id == eid).count(); db.close()
        if n >= 1:
            break
        import time; time.sleep(0.5)
    db = next(get_db()); rows = db.query(ChatSummary).filter(ChatSummary.elder_id == eid).all(); db.close()
    print(f"[落库条数] {len(rows)}")
    assert len(rows) >= 1, "症状问答未落库！BUG复现"
    row = rows[0]
    print(f"  category={row.category} summary={row.summary} risk={row.risk} module={row.module} synced={row.synced}")
    assert row.category == "selfcheck" and row.summary and row.synced is False

    # 场景2：教程类问题 → 不应落库
    client.post("/api/chat", json={"question": "怎么搜索微信小程序"}, headers=h)
    for _ in range(10):
        db = next(get_db()); n = db.query(ChatSummary).filter(ChatSummary.elder_id == eid).count(); db.close()
        if n > len(rows): break
        import time; time.sleep(0.5)
    db = next(get_db()); n2 = db.query(ChatSummary).filter(ChatSummary.elder_id == eid).count(); db.close()
    print(f"[教程问题落库条数应仍={len(rows)}，实际={n2}]")
    assert n2 == len(rows), "教程类问题错误落库"

    # 场景3：匿名(无token) → 不应落库
    client.post("/api/chat", json={"question": "我这两天头晕"})
    for _ in range(10):
        db = next(get_db()); n3 = db.query(ChatSummary).filter(ChatSummary.elder_id == eid).count(); db.close()
        if n3 > n2: break
        import time; time.sleep(0.5)
    db = next(get_db()); n4 = db.query(ChatSummary).filter(ChatSummary.elder_id == eid).count(); db.close()
    print(f"[匿名问题落库条数应仍={n2}，实际={n4}]")
    assert n4 == n2, "匿名请求错误落库"

    # 场景3b（BUG-009 修复）：LLM 摘要提炼失败 → 兜底用问题落库，健康类记录不丢失
    core.chat_summary.call_qwen = lambda sp, up: "NONE"   # 模拟本地LLM不可用/提炼失败
    client.post("/api/chat", json={"question": "我血压有点高，怎么办"}, headers=h)
    for _ in range(20):
        db = next(get_db()); n5 = db.query(ChatSummary).filter(ChatSummary.elder_id == eid).count(); db.close()
        if n5 > n4: break
        import time; time.sleep(0.5)
    db = next(get_db()); n6 = db.query(ChatSummary).filter(ChatSummary.elder_id == eid).count(); db.close()
    print(f"[LLM失败兜底: 应>={n4+1}，实际={n6}]")
    assert n6 >= n4 + 1, "BUG-009未修复：LLM失败时健康类对话仍未落库"
    # 校验兜底摘要 = 问题截断
    last = db.query(ChatSummary).filter(ChatSummary.elder_id == eid).order_by(ChatSummary.id.desc()).first()
    assert "血压" in last.summary, f"兜底摘要异常: {last.summary}"
    print(f"  兜底摘要: {last.summary}")
    core.chat_summary.call_qwen = fake_qwen

    # 场景4：sync 是否带出 chat_summaries（隐私开关默认开）
    # 先造一个家属绑定
    fp = f"13{random.randint(0, 999999999):09d}"
    client.post("/api/auth/register", json={"phone": fp, "password": "123456", "nickname": "小张", "role": "family"}).status_code == 201
    f_tok = client.post("/api/auth/login", json={"phone": fp, "password": "123456"}).json()["access_token"]
    inv = client.post("/api/bind/invite", headers=h).json()
    client.post("/api/bind/accept", json={"invite_code": inv["invite_code"], "elder_id": eid}, headers={"Authorization": f"Bearer {f_tok}"})
    syn = client.get(f"/api/sync?elder_id={eid}", headers={"Authorization": f"Bearer {f_tok}"}).json()
    print(f"[sync.chat_summaries条数] {len(syn['chat_summaries'])}")
    assert len(syn["chat_summaries"]) >= 1, "sync未带出对话摘要！BUG复现"

    # 场景5：隐私开关关闭 → sync 的 chat_summaries 应空
    client.put("/api/privacy", json={"sync_summary_to_family": False}, headers=h)
    syn2 = client.get(f"/api/sync?elder_id={eid}", headers={"Authorization": f"Bearer {f_tok}"}).json()
    print(f"[开关关闭后sync.chat_summaries条数] {len(syn2['chat_summaries'])}")
    assert len(syn2["chat_summaries"]) == 0, "隐私开关关闭仍返回摘要"
    client.put("/api/privacy", json={"sync_summary_to_family": True}, headers=h)

    # 清理
    db = next(get_db())
    db.query(ChatSummary).filter(ChatSummary.elder_id == eid).delete()
    u1 = db.query(User).filter(User.phone == ep).first()
    u2 = db.query(User).filter(User.phone == fp).first()
    for u in (u1, u2):
        if u: db.delete(u)
    db.commit(); db.close()

    print("\n✅ 对话摘要自动提取链路全部验证通过（落库/分类/匿名不落库/sync/隐私开关）")
    print("   说明：后端链路正常，BUG-009 若仍不生效，根因在『前端/老人登录态』——")


if __name__ == "__main__":
    main()

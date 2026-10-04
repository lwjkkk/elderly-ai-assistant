# 功能2验证：对话摘要分类 + 落库 + GET /api/chat/summaries（mock LLM，不依赖 Ollama）
import random

from fastapi.testclient import TestClient

from db.database import init_db, get_db, SessionLocal
from db.models import User, ChatSummary
from core import chat_summary
from core.chat_summary import classify_category, save_summary_sync
from main import app

init_db()
client = TestClient(app)


def _reg(phone, role, nick):
    r = client.post("/api/auth/register", json={"phone": phone, "password": "123456", "nickname": nick, "role": role})
    assert r.status_code == 201, r.text
    tok = client.post("/api/auth/login", json={"phone": phone, "password": "123456"}).json()["access_token"]
    return tok


def main():
    # --- 1) 分类判定（不落库） ---
    assert classify_category("这两天头晕") == "selfcheck", classify_category("这两天头晕")
    assert classify_category("这个药是做什么的") == "drug"
    assert classify_category("我该什么时候吃药") == "med"
    assert classify_category("怎么挂号去医院") == "consult"
    assert classify_category("微信怎么打视频电话") is None  # 教程类不落库
    print("[分类判定] 通过：selfcheck/drug/med/consult 识别，教程类不落库")

    # --- 2) mock LLM 后走完整落库链路 ---
    chat_summary.call_qwen = lambda sp, up: "SUMMARY: 近两日头晕，建议监测血压"
    elder_phone = f"13{random.randint(0, 999999999):09d}"
    fam_phone = f"13{random.randint(0, 999999999):09d}"
    e_tok = _reg(elder_phone, "elder", "测试老人")
    f_tok = _reg(fam_phone, "family", "测试家属")

    db = next(get_db())
    eid = db.query(User).filter(User.phone == elder_phone).first().id
    fid = db.query(User).filter(User.phone == fam_phone).first().id

    ok = save_summary_sync(eid, "这两天头晕，有点不舒服", "建议监测血压，注意休息", "health")
    print("[落库结果]", ok)
    assert ok, "应成功落库"
    # 教程类问题不应落库
    ok2 = save_summary_sync(eid, "微信怎么打视频电话", "第一步...", "phone")
    assert ok2 is False, "教程类不应落库"
    print("[落库过滤] 通过：健康类落库、教程类跳过")

    # --- 3) GET summaries 权限与内容 ---
    # 家属需绑定
    inv = client.post("/api/bind/invite", headers={"Authorization": f"Bearer {e_tok}"}).json()
    client.post("/api/bind/accept", json={"invite_code": inv["invite_code"], "elder_id": eid},
                headers={"Authorization": f"Bearer {f_tok}"})

    r = client.get("/api/chat/summaries", headers={"Authorization": f"Bearer {e_tok}"})
    print("[老人GET summaries]", r.status_code, len(r.json()))
    assert r.status_code == 200 and len(r.json()) >= 1
    s = r.json()[0]
    assert s["category"] == "selfcheck" and "血压" in s["summary"]
    print("[内容]", s["category"], "|", s["summary"], "| risk=", s.get("risk"))

    r = client.get(f"/api/chat/summaries?elder_id={eid}&category=selfcheck",
                   headers={"Authorization": f"Bearer {f_tok}"})
    print("[家属按老人查]", r.status_code, len(r.json()))
    assert r.status_code == 200 and all(x["category"] == "selfcheck" for x in r.json())

    # 家属不指定 elder_id 应 400
    r = client.get("/api/chat/summaries", headers={"Authorization": f"Bearer {f_tok}"})
    print("[家属未指定elder]", r.status_code)
    assert r.status_code == 400

    # --- 清理 ---
    db2 = SessionLocal()
    db2.query(ChatSummary).filter(ChatSummary.elder_id == eid).delete()
    for p in (elder_phone, fam_phone):
        u = db2.query(User).filter(User.phone == p).first()
        if u:
            db2.delete(u)
    db2.commit(); db2.close()

    print("\n✅ 功能2全部通过：4类识别、健康类落库、教程类跳过、summaries权限与过滤正确")


if __name__ == "__main__":
    main()

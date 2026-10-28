
# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
# 功能4验证：/api/sync 扩展 drug_queries、chat_summaries（受隐私开关约束）
import random

from fastapi.testclient import TestClient

from db.database import init_db, get_db, SessionLocal
from db.models import User, DrugQuery, ChatSummary
import api.drugs
import core.chat_summary
from main import app

init_db()
client = TestClient(app)


def _reg(phone, role, nick):
    assert client.post("/api/auth/register", json={"phone": phone, "password": "123456", "nickname": nick, "role": role}).status_code == 201
    return client.post("/api/auth/login", json={"phone": phone, "password": "123456"}).json()["access_token"]


def main():
    elder_phone = f"13{random.randint(0, 999999999):09d}"
    fam_phone = f"13{random.randint(0, 999999999):09d}"
    e_tok = _reg(elder_phone, "elder", "测试老人")
    f_tok = _reg(fam_phone, "family", "测试家属")

    db = next(get_db())
    eid = db.query(User).filter(User.phone == elder_phone).first().id
    fid = db.query(User).filter(User.phone == fam_phone).first().id
    db.close()
    inv = client.post("/api/bind/invite", headers={"Authorization": f"Bearer {e_tok}"}).json()
    client.post("/api/bind/accept", json={"invite_code": inv["invite_code"], "elder_id": eid},
                headers={"Authorization": f"Bearer {f_tok}"})

    # mock LLM（查药 + 摘要）
    api.drugs.call_qwen = lambda sp, up: "阿司匹林用于缓解疼痛。禁忌与副作用以说明书为准。"
    core.chat_summary.call_qwen = lambda sp, up: "SUMMARY: 老人近期咨询降压药用法，建议按医嘱规律服药"

    # 产生一条查药记录 + 一条对话摘要
    assert client.post("/api/drugs/query-name", json={"name": "阿司匹林"},
                       headers={"Authorization": f"Bearer {e_tok}"}).status_code == 200
    core.chat_summary.save_summary_sync(eid, "降压药什么时候吃", "早上饭后吃，遵医嘱", "health")

    # 1) 家属 sync：开关默认开，应含 drug_queries + chat_summaries
    r = client.get(f"/api/sync?elder_id={eid}", headers={"Authorization": f"Bearer {f_tok}"})
    print("[家属sync(开关开)]", r.status_code)
    assert r.status_code == 200
    body = r.json()
    assert "drug_queries" in body and "chat_summaries" in body
    assert len(body["drug_queries"]) >= 1, "应有查药记录"
    assert len(body["chat_summaries"]) >= 1, "应有对话摘要"
    print("  drug_queries条数", len(body["drug_queries"]), "| chat_summaries条数", len(body["chat_summaries"]))

    # 2) 老人关闭隐私开关
    assert client.put("/api/privacy", json={"sync_summary_to_family": False},
                      headers={"Authorization": f"Bearer {e_tok}"}).status_code == 200

    # 3) 家属 sync：chat_summaries 应为空，drug_queries 仍在
    r = client.get(f"/api/sync?elder_id={eid}", headers={"Authorization": f"Bearer {f_tok}"})
    body = r.json()
    assert body["chat_summaries"] == [], "开关关闭时 chat_summaries 应为空"
    assert len(body["drug_queries"]) >= 1, "查药记录不受开关影响"
    print("[家属sync(开关关)] chat_summaries=[]，drug_queries仍", len(body["drug_queries"]), "条")

    # 4) 老人自己 sync 同样受开关约束
    r = client.get("/api/sync", headers={"Authorization": f"Bearer {e_tok}"})
    body = r.json()
    assert body["chat_summaries"] == [], "老人视角开关关闭也应返回空"

    # 清理
    db2 = SessionLocal()
    db2.query(ChatSummary).filter(ChatSummary.elder_id == eid).delete()
    db2.query(DrugQuery).filter(DrugQuery.elder_id == eid).delete()
    for p in (elder_phone, fam_phone):
        u = db2.query(User).filter(User.phone == p).first()
        if u:
            db2.delete(u)
    db2.commit(); db2.close()

    print("\n✅ 功能4全部通过：sync含新字段、开关关闭时chat_summaries为空、drug_queries不受影响")


if __name__ == "__main__":
    main()

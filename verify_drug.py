# 功能3验证：查药落库 + GET /api/drugs/records（mock LLM，不依赖 Ollama）
import random

from fastapi.testclient import TestClient

from db.database import init_db, get_db, SessionLocal
from db.models import User, DrugQuery
import api.drugs
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

    # mock LLM
    api.drugs.call_qwen = lambda sp, up: ("阿司匹林是常用的解热镇痛药，主要用于缓解轻度疼痛和退烧。"
                                          "禁忌：对阿司匹林过敏者禁用，有胃溃疡史者慎用。副作用：可能引起胃部不适。")

    # 1) 老人按名查药（落库）
    r = client.post("/api/drugs/query-name", json={"name": "阿司匹林"},
                    headers={"Authorization": f"Bearer {e_tok}"})
    print("[老人按名查药]", r.status_code)
    assert r.status_code == 200

    # 2) 老人查自己记录
    r = client.get("/api/drugs/records", headers={"Authorization": f"Bearer {e_tok}"})
    print("[老人GET records]", r.status_code, "条数", len(r.json()))
    assert r.status_code == 200 and len(r.json()) >= 1
    rec = r.json()[0]
    assert rec["kind"] == "name" and rec["input_text"] == "阿司匹林" and rec["explanation"]
    print("[记录内容]", rec["kind"], "|", rec["input_text"], "| 解读长度", len(rec["explanation"]))

    # 3) 家属指定 elder 查
    r = client.get(f"/api/drugs/records?elder_id={eid}", headers={"Authorization": f"Bearer {f_tok}"})
    print("[家属按老人查]", r.status_code, "条数", len(r.json()))
    assert r.status_code == 200 and len(r.json()) >= 1

    # 4) 家属不指定 elder → 400
    r = client.get("/api/drugs/records", headers={"Authorization": f"Bearer {f_tok}"})
    print("[家属未指定elder]", r.status_code)
    assert r.status_code == 400

    # 清理
    db2 = SessionLocal()
    db2.query(DrugQuery).filter(DrugQuery.elder_id == eid).delete()
    for p in (elder_phone, fam_phone):
        u = db2.query(User).filter(User.phone == p).first()
        if u:
            db2.delete(u)
    db2.commit(); db2.close()

    print("\n✅ 功能3全部通过：查药落库、老人/家属可查、未绑定家属400")


if __name__ == "__main__":
    main()

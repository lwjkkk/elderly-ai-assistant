# P2 验证：export空数据400、四列表接口认elder_id
import random

from fastapi.testclient import TestClient

from db.database import init_db, get_db
from db.models import User
from main import app

init_db()
client = TestClient(app)


def main():
    ep = f"13{random.randint(0, 999999999):09d}"
    fp = f"13{random.randint(0, 999999999):09d}"
    for p, role, nick in [(ep, "elder", "测试老人"), (fp, "family", "测试家属")]:
        assert client.post("/api/auth/register", json={"phone": p, "password": "123456", "nickname": nick, "role": role}).status_code == 201
    e_tok = client.post("/api/auth/login", json={"phone": ep, "password": "123456"}).json()["access_token"]
    f_tok = client.post("/api/auth/login", json={"phone": fp, "password": "123456"}).json()["access_token"]
    db = next(get_db())
    eid = db.query(User).filter(User.phone == ep).first().id
    db.close()
    inv = client.post("/api/bind/invite", headers={"Authorization": f"Bearer {e_tok}"}).json()
    client.post("/api/bind/accept", json={"invite_code": inv["invite_code"], "elder_id": eid}, headers={"Authorization": f"Bearer {f_tok}"})

    # P2-2：体征无数据时 export 返回 400 + 中文
    r = client.get(f"/api/vitals/export?elder_id={eid}", headers={"Authorization": f"Bearer {f_tok}"})
    print("[export空数据]", r.status_code, r.json())
    assert r.status_code == 400 and "暂无体征记录" in r.json()["detail"]

    # P2-3：四列表接口，家属指定 elder_id 均可用（空列表或200）
    for path in [f"/api/vitals?elder_id={eid}", f"/api/reports?elder_id={eid}",
                 f"/api/consults?elder_id={eid}", f"/api/symptom-check?elder_id={eid}"]:
        r = client.get(path, headers={"Authorization": f"Bearer {f_tok}"})
        print(f"[{path}] {r.status_code} 条数 {len(r.json())}")
        assert r.status_code == 200

    # 家属不指定 elder_id → 400（四接口都应 400）
    for path in ["/api/vitals", "/api/reports", "/api/consults", "/api/symptom-check"]:
        r = client.get(path, headers={"Authorization": f"Bearer {f_tok}"})
        assert r.status_code == 400, f"{path} 应400"
    print("[家属未指定elder→400] 四接口均通过")

    # 清理
    db = next(get_db())
    for p in (ep, fp):
        u = db.query(User).filter(User.phone == p).first()
        if u:
            db.delete(u)
    db.commit(); db.close()

    print("\n✅ P2全部通过：export空数据400、四列表接口认elder_id")


if __name__ == "__main__":
    main()

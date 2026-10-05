# 隐私开关接口验证：elder 可读可写；family 读写均 403
import random

from fastapi.testclient import TestClient

from db.database import init_db
from main import app

init_db()  # TestClient 不自动触发 lifespan，需手动建表/补列
client = TestClient(app)


def token(phone, password="123456"):
    r = client.post("/api/auth/login", json={"phone": phone, "password": password})
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def main():
    # 用两个随机号，避免污染既有数据
    elder_phone = f"13{random.randint(0, 999999999):09d}"
    fam_phone = f"13{random.randint(0, 999999999):09d}"
    # 注册老人+家属
    for p, role, nick in [(elder_phone, "elder", "测试老人"), (fam_phone, "family", "测试家属")]:
        r = client.post("/api/auth/register", json={"phone": p, "password": "123456", "nickname": nick, "role": role})
        assert r.status_code == 201, r.text
    # 建立绑定（家属要能拿到 elder_id）
    e = client.post("/api/auth/login", json={"phone": elder_phone, "password": "123456"}).json()
    elder_token = e["access_token"]
    f = client.post("/api/auth/login", json={"phone": fam_phone, "password": "123456"}).json()
    fam_token = f["access_token"]
    elder_id = client.get("/api/auth/refresh", headers={"Authorization": f"Bearer {elder_token}"}).json()  # 无 id
    # 从登录响应拿不到 id，改用数据库查
    from db.database import get_db
    from db.models import User
    db = next(get_db())
    eid = db.query(User).filter(User.phone == elder_phone).first().id
    fid = db.query(User).filter(User.phone == fam_phone).first().id
    db.close()

    # 老人生成邀请码，家属接受绑定
    inv = client.post("/api/bind/invite", headers={"Authorization": f"Bearer {elder_token}"}).json()
    client.post("/api/bind/accept", json={"invite_code": inv["invite_code"], "elder_id": eid},
                headers={"Authorization": f"Bearer {fam_token}"})

    # 1) 老人 GET 默认应为 true
    r = client.get("/api/privacy", headers={"Authorization": f"Bearer {elder_token}"})
    print("[老人GET默认]", r.status_code, r.json())
    assert r.status_code == 200 and r.json()["sync_summary_to_family"] is True

    # 2) 老人 PUT 关闭
    r = client.put("/api/privacy", json={"sync_summary_to_family": False},
                   headers={"Authorization": f"Bearer {elder_token}"})
    print("[老人PUT关闭]", r.status_code, r.json())
    assert r.json()["sync_summary_to_family"] is False

    # 3) 老人 GET 回读最新值
    r = client.get("/api/privacy", headers={"Authorization": f"Bearer {elder_token}"})
    print("[老人GET回读]", r.status_code, r.json())
    assert r.json()["sync_summary_to_family"] is False

    # 4) 老人 PUT 恢复 true
    r = client.put("/api/privacy", json={"sync_summary_to_family": True},
                   headers={"Authorization": f"Bearer {elder_token}"})
    print("[老人PUT恢复]", r.status_code, r.json())

    # 5) 家属 GET 应 403
    r = client.get("/api/privacy", headers={"Authorization": f"Bearer {fam_token}"})
    print("[家属GET]", r.status_code, r.json())
    assert r.status_code == 403

    # 6) 家属 PUT 应 403
    r = client.put("/api/privacy", json={"sync_summary_to_family": False},
                   headers={"Authorization": f"Bearer {fam_token}"})
    print("[家属PUT]", r.status_code, r.json())
    assert r.status_code == 403

    # 清理测试账号
    for p in (elder_phone, fam_phone):
        db = next(get_db())
        u = db.query(User).filter(User.phone == p).first()
        if u:
            db.delete(u); db.commit()
        db.close()

    print("\n✅ 隐私开关全部通过：elder可读可写、family 403、值正确持久化")


if __name__ == "__main__":
    main()

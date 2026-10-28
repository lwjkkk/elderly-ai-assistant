
# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
# P0 验证：bind/invite 放开权限（elder/family 均 200）；查药 records 接口存在可用
import random

from fastapi.testclient import TestClient

from db.database import init_db, get_db
from db.models import User
from main import app

init_db()
client = TestClient(app)


def main():
    # 注册 elder + family
    ep = f"13{random.randint(0, 999999999):09d}"
    fp = f"13{random.randint(0, 999999999):09d}"
    for p, role, nick in [(ep, "elder", "测试老人"), (fp, "family", "测试家属")]:
        assert client.post("/api/auth/register", json={"phone": p, "password": "123456", "nickname": nick, "role": role}).status_code == 201
    e_tok = client.post("/api/auth/login", json={"phone": ep, "password": "123456"}).json()["access_token"]
    f_tok = client.post("/api/auth/login", json={"phone": fp, "password": "123456"}).json()["access_token"]

    # P0-1：elder 调 invite → 200
    r = client.post("/api/bind/invite", headers={"Authorization": f"Bearer {e_tok}"})
    print("[老人生成邀请码]", r.status_code, r.json())
    assert r.status_code == 200 and r.json()["invite_code"]

    # P0-1：family 调 invite → 200（放开权限）
    r = client.post("/api/bind/invite", headers={"Authorization": f"Bearer {f_tok}"})
    print("[家属生成邀请码]", r.status_code, r.json())
    assert r.status_code == 200 and r.json()["invite_code"], "家属生成邀请码应成功（P0放开权限）"

    # P0-2：查药 records 接口存在，老人可调用（空列表也算正常）
    r = client.get("/api/drugs/records", headers={"Authorization": f"Bearer {e_tok}"})
    print("[查药records]", r.status_code, "条数", len(r.json()))
    assert r.status_code == 200, "查药记录列表接口应可用"

    # 清理
    db = next(get_db())
    for p in (ep, fp):
        u = db.query(User).filter(User.phone == p).first()
        if u:
            db.delete(u)
    db.commit(); db.close()

    print("\n✅ P0全部通过：invite对elder/family均放开；查药records接口存在可用")


if __name__ == "__main__":
    main()

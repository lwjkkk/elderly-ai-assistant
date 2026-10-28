
# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
# 用户资料接口验证：PUT/GET /api/users/profile + 头像上传 + 鉴权本人校验
import base64
import random
import io

from fastapi.testclient import TestClient

from db.database import init_db, get_db
from db.models import User
from main import app

init_db()
client = TestClient(app)

# 生成一张极小 jpg（头像用）
def tiny_jpg_b64():
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (512, 512), (200, 120, 60)).save(buf, format="JPEG")
    return base64.b64encode(buf.getvalue()).decode()


def main():
    ep = f"13{random.randint(0, 999999999):09d}"
    r = client.post("/api/auth/register", json={"phone": ep, "password": "123456", "nickname": "初始名", "role": "elder"})
    assert r.status_code == 201, r.text
    tok = client.post("/api/auth/login", json={"phone": ep, "password": "123456"}).json()["access_token"]
    h = {"Authorization": f"Bearer {tok}"}
    uid = next(get_db()).query(User).filter(User.phone == ep).first().id

    # 场景1：只改昵称
    r = client.put("/api/users/profile", json={"nickname": "hlf"}, headers=h)
    print("[只改昵称]", r.status_code, r.json())
    assert r.status_code == 200 and r.json()["nickname"] == "hlf"
    assert r.json()["id"] == uid

    # 场景2：性别枚举校验（非法值应 400）
    r = client.put("/api/users/profile", json={"gender": "中性"}, headers=h)
    print("[非法性别]", r.status_code)
    assert r.status_code == 400

    # 场景3：正常改性别+出生年月
    r = client.put("/api/users/profile", json={"gender": "男", "birth_ym": "1955-08"}, headers=h)
    print("[性别+出生]", r.status_code, r.json())
    assert r.status_code == 200 and r.json()["gender"] == "男" and r.json()["birth_ym"] == "1955-08"

    # 场景4：birth_ym 格式非法
    r = client.put("/api/users/profile", json={"birth_ym": "1955-8"}, headers=h)
    print("[非法出生月]", r.status_code)
    assert r.status_code == 400

    # 场景5：性别设空字符串=清除
    r = client.put("/api/users/profile", json={"gender": ""}, headers=h)
    print("[性别清空]", r.status_code, "gender=", r.json()["gender"])
    assert r.status_code == 200 and r.json()["gender"] is None

    # 场景6：上传头像（base64）
    r = client.put("/api/users/profile", json={"avatar_base64": tiny_jpg_b64()}, headers=h)
    print("[上传头像]", r.status_code, "avatar_url=", r.json().get("avatar_url"))
    assert r.status_code == 200 and r.json()["avatar_url"] and r.json()["avatar_url"].startswith("/api/users/avatar/")
    avatar_url = r.json()["avatar_url"]
    # 头像可访问
    r2 = client.get(avatar_url)
    print("[头像GET]", r2.status_code, "bytes=", len(r2.content))
    assert r2.status_code == 200 and len(r2.content) > 0

    # 场景7：GET 拉取完整资料（模拟换设备登录刷新）
    r = client.get("/api/users/profile", headers=h)
    print("[GET资料]", r.status_code, r.json())
    assert r.status_code == 200 and r.json()["nickname"] == "hlf" and r.json()["avatar_url"] == avatar_url

    # 场景8：未带 token 应 401
    r = client.put("/api/users/profile", json={"nickname": "x"})
    print("[无token]", r.status_code)
    assert r.status_code == 401

    # 场景9：本人只能改自己——用另一个用户 token 改这个用户（不带 elder_id 参数，天然只认 current）
    fp = f"13{random.randint(0, 999999999):09d}"
    client.post("/api/auth/register", json={"phone": fp, "password": "123456", "nickname": "别的", "role": "family"})
    f_tok = client.post("/api/auth/login", json={"phone": fp, "password": "123456"}).json()["access_token"]
    r = client.put("/api/users/profile", json={"nickname": "我改别人"}, headers={"Authorization": f"Bearer {f_tok}"})
    print("[家属改自己]", r.status_code, r.json().get("nickname"))
    # 家属 token 改的是家属自己，不影响老人
    db = next(get_db())
    elder = db.query(User).filter(User.id == uid).first()
    fam = db.query(User).filter(User.phone == fp).first()
    assert elder.nickname == "hlf", "老人昵称被他人改动！越权"
    assert fam.nickname == "我改别人"
    db.close()

    # 清理
    db = next(get_db())
    for u in (db.query(User).filter(User.id == uid).first(), db.query(User).filter(User.phone == fp).first()):
        if u: db.delete(u)
    db.commit(); db.close()

    print("\n✅ 用户资料接口全部验证通过（多端同步/校验/鉴权本人/头像存取）")


if __name__ == "__main__":
    main()

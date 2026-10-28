
# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
# 临时边界测试：手机号格式 + 邀请码有效期
from fastapi import FastAPI
from fastapi.testclient import TestClient
from datetime import datetime, timedelta, timezone

from api.auth import router as auth_router
from api.bind import router as bind_router
from db.database import Base, engine, SessionLocal
from db.models import FamilyBinding

app = FastAPI()
app.include_router(auth_router)
app.include_router(bind_router)
Base.metadata.drop_all(bind=engine)
Base.metadata.create_all(bind=engine)
c = TestClient(app)

# 准备合法老人/家属
c.post("/api/auth/register", json={"phone":"13800000001","password":"123456","nickname":"张奶奶","role":"elder"})
c.post("/api/auth/register", json={"phone":"13800000002","password":"123456","nickname":"小张","role":"family"})

print("=====手机号格式校验（应全部 422）=====")
for bad in ["12345", "12345678901", "23800000001", "abcdefghijk"]:
    r = c.post("/api/auth/register", json={"phone":bad,"password":"123456","nickname":"x","role":"elder"})
    print(f"  {bad} -> {r.status_code}")

print("=====邀请码过期测试=====")
et = c.post("/api/auth/login", json={"phone":"13800000001","password":"123456"}).json()["access_token"]
ft = c.post("/api/auth/login", json={"phone":"13800000002","password":"123456"}).json()["access_token"]

code = c.post("/api/bind/invite", headers={"Authorization":f"Bearer {et}"}).json()["invite_code"]
# 手动把该码创建时间改成 1 小时前，模拟过期
db = SessionLocal()
b = db.query(FamilyBinding).filter(FamilyBinding.invite_code==code).first()
b.created_at = datetime.now(timezone.utc) - timedelta(hours=1)
db.commit(); db.close()

r = c.post("/api/bind/accept", json={"invite_code":code}, headers={"Authorization":f"Bearer {ft}"})
print("  过期码 ->", r.status_code, r.json()["detail"])

code2 = c.post("/api/bind/invite", headers={"Authorization":f"Bearer {et}"}).json()["invite_code"]
r = c.post("/api/bind/accept", json={"invite_code":code2}, headers={"Authorization":f"Bearer {ft}"})
print("  正常新码 ->", r.status_code, r.json()["status"])

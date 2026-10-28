
# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
# Day1 验收脚本：临时验证 注册/登录/绑定 全链路
# 这里用只含鉴权+绑定的最小 app，避免拉起 torch/paddle 等重依赖
from fastapi import FastAPI
from fastapi.testclient import TestClient
from api.auth import router as auth_router
from api.bind import router as bind_router
from db.database import Base, engine

app = FastAPI()
app.include_router(auth_router)
app.include_router(bind_router)
# 每次先清空再建表，保证重复运行都是干净状态（这是测试脚本，不影响正式数据）
Base.metadata.drop_all(bind=engine)
Base.metadata.create_all(bind=engine)
c = TestClient(app)

# 1. 注册老人
r = c.post("/api/auth/register", json={
    "phone": "13800000001", "password": "123456",
    "nickname": "张奶奶", "role": "elder"})
print("注册老人:", r.status_code, r.json())

# 2. 注册家属
r = c.post("/api/auth/register", json={
    "phone": "13800000002", "password": "123456",
    "nickname": "小张", "role": "family"})
print("注册家属:", r.status_code, r.json())

# 3. 老人登录 + 生成邀请码
r = c.post("/api/auth/login", json={"phone": "13800000001", "password": "123456"})
elder_token = r.json()["access_token"]
print("老人登录:", r.status_code)

r = c.post("/api/bind/invite", headers={"Authorization": f"Bearer {elder_token}"})
code = r.json()["invite_code"]
print("老人生成邀请码:", code)

# 4. 家属登录 + 接受绑定
r = c.post("/api/auth/login", json={"phone": "13800000002", "password": "123456"})
fam_token = r.json()["access_token"]

r = c.post("/api/bind/accept", json={"invite_code": code},
           headers={"Authorization": f"Bearer {fam_token}"})
print("家属接受绑定:", r.status_code, r.json())

# 5. 老人查询绑定列表
r = c.get("/api/bind/list", headers={"Authorization": f"Bearer {elder_token}"})
print("老人视角绑定列表:", r.json())

# 断言
assert r.json()[0]["status"] == "active", "绑定状态应为 active"
print("\n✅ Day1 三连跑通：注册老人+家属 → 输码绑定 → 状态 active")

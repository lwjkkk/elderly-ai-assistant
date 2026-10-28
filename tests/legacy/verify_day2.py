
# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
# Day2 验收：录药 -> 到点推送 -> 打卡 -> 家属同步 -> 漏服判定
# 用构造的时间调用定时纯函数，无需真实等待；查药(OCR+LLM)需完整环境另测。
from datetime import datetime

from fastapi import FastAPI
from fastapi.testclient import TestClient

from api.auth import router as auth_router
from api.bind import router as bind_router
from api.meds import router as meds_router
from db.database import Base, engine
from services import push
from services.scheduler import run_reminder_cycle, run_missed_cycle

app = FastAPI()
for r in (auth_router, bind_router, meds_router):
    app.include_router(r)
Base.metadata.drop_all(bind=engine)
Base.metadata.create_all(bind=engine)
c = TestClient(app)
push.clear_sent()


def H(token):
    return {"Authorization": f"Bearer {token}"}


# 注册老人/家属 + 绑定
c.post("/api/auth/register", json={"phone":"13800000001","password":"123456","nickname":"张奶奶","role":"elder"})
c.post("/api/auth/register", json={"phone":"13800000002","password":"123456","nickname":"小张","role":"family"})
et = c.post("/api/auth/login", json={"phone":"13800000001","password":"123456"}).json()["access_token"]
ft = c.post("/api/auth/login", json={"phone":"13800000002","password":"123456"}).json()["access_token"]
code = c.post("/api/bind/invite", headers=H(et)).json()["invite_code"]
c.post("/api/bind/accept", json={"invite_code": code}, headers=H(ft))

# 1. 家属代老人录药：阿司匹林 每日1次 08:00
r = c.post("/api/meds", headers=H(ft), json={
    "name":"阿司匹林","dosage":"1片","frequency":"每日1次","times":["08:00"],"elder_id":1})
med_id = r.json()["id"]
print("家属代录药:", r.status_code, r.json()["name"])

# 2. 模拟 08:00 到点，推送（应通知老人 id1 和家属 id2）
pushed = run_reminder_cycle(now=datetime(2026, 9, 30, 8, 0, 0))
print("到点推送条数:", len(pushed), "接收人:", [p["receiver_id"] for p in pushed])

# 3. 老人打卡 08:00
r = c.post("/api/meds/checkin", headers=H(et),
           json={"medication_id":med_id,"slot":"08:00","date":"2026-09-30"})
print("老人打卡:", r.status_code, r.json()["status"])

# 4. 家属查今日清单（应看到 08:00 taken）
r = c.get("/api/meds/today?elder_id=1&date=2026-09-30", headers=H(ft))
print("家属看今日清单:", r.json())

# 5. 漏服：再录降压药 07:00，模拟现在 09:00（超过30分钟宽限）
c.post("/api/meds", headers=H(ft), json={
    "name":"降压药","dosage":"1片","frequency":"每日1次","times":["07:00"],"elder_id":1})
missed = run_missed_cycle(now=datetime(2026, 9, 30, 9, 0, 0))
print("漏服判定:", missed)

# 断言
assert len(pushed) == 2, "应推送给老人和家属"
assert r.json()[0]["slots"][0]["status"] == "taken"
assert any(m["slot"] == "07:00" for m in missed)
print("\nDay2 闭环跑通：录药->到点推送->打卡->家属同步->漏服判定")

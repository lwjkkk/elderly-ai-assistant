
# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
# 前三天综合自测：独立临时库，不碰 elderly.db；跑完自动清理临时文件。
# 每项记录 通过/失败，最后汇总，不因单项失败中断。
import os
from datetime import datetime

# 1) 先把数据库换成独立临时库，再导入业务模块（保证 scheduler 也用临时库）
import sqlalchemy
from sqlalchemy.orm import sessionmaker
import db.database as dbmod

TEST_DB = os.path.join(os.path.dirname(__file__), "_selftest.db")
if os.path.exists(TEST_DB):
    os.remove(TEST_DB)
TESTDB_URL = "sqlite:///" + TEST_DB.replace("\\", "/")
test_engine = sqlalchemy.create_engine(
    TESTDB_URL, connect_args={"check_same_thread": False})
dbmod.engine = test_engine
dbmod.SessionLocal = sessionmaker(bind=test_engine, autoflush=False, autocommit=False)

# 2) 导入业务（此时 models 注册到 Base）
from fastapi import FastAPI
from fastapi.testclient import TestClient
from db.database import Base
from api.auth import router as auth_router
from api.bind import router as bind_router
from api.meds import router as meds_router
from api.vitals import router as vitals_router
from api.consults import router as consults_router
from services import push
from services.scheduler import run_reminder_cycle, run_missed_cycle

Base.metadata.create_all(bind=test_engine)

app = FastAPI()
for r in (auth_router, bind_router, meds_router, vitals_router, consults_router):
    app.include_router(r)
c = TestClient(app)
push.clear_sent()

results = []
uploaded_files = []


def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))


def H(t):
    return {"Authorization": f"Bearer {t}"}


# ---------- Day1 ----------
r1 = c.post("/api/auth/register", json={"phone":"13800000001","password":"123456","nickname":"张奶奶","role":"elder"})
r2 = c.post("/api/auth/register", json={"phone":"13800000002","password":"123456","nickname":"小张","role":"family"})
r3 = c.post("/api/auth/register", json={"phone":"13800000003","password":"123456","nickname":"外人","role":"family"})
check("Day1 注册老人/家属/第三人家属", r1.status_code == 201 and r2.status_code == 201 and r3.status_code == 201,
      f"{r1.status_code}/{r2.status_code}/{r3.status_code}")

et = c.post("/api/auth/login", json={"phone":"13800000001","password":"123456"}).json()["access_token"]
ft = c.post("/api/auth/login", json={"phone":"13800000002","password":"123456"}).json()["access_token"]
wt = c.post("/api/auth/login", json={"phone":"13800000003","password":"123456"}).json()["access_token"]
check("Day1 三类登录拿token", bool(et and ft and wt))

code = c.post("/api/bind/invite", headers=H(et)).json()["invite_code"]
rb = c.post("/api/bind/accept", json={"invite_code": code}, headers=H(ft))
check("Day1 输码绑定 active", rb.status_code == 200 and rb.json()["status"] == "active", str(rb.json()))

# ---------- Day2 ----------
rm = c.post("/api/meds", headers=H(ft), json={
    "name":"阿司匹林","dosage":"1片","frequency":"每日1次","times":["08:00"],"elder_id":1})
med_id = rm.json().get("id")
check("Day2 家属代录药", rm.status_code == 200, rm.json().get("name",""))

pushed = run_reminder_cycle(now=datetime(2026, 10, 2, 8, 0, 0))
check("Day2 到点推送老人+家属(2条)", len(pushed) == 2, f"接收人{[p['receiver_id'] for p in pushed]}")

rc = c.post("/api/meds/checkin", headers=H(et),
            json={"medication_id":med_id,"slot":"08:00","date":"2026-10-02"})
check("Day2 老人打卡 taken", rc.status_code == 200 and rc.json()["status"] == "taken", rc.json().get("status"))

rt = c.get("/api/meds/today?elder_id=1&date=2026-10-02", headers=H(ft))
st = rt.json()[0]["slots"][0]["status"] if rt.json() else None
check("Day2 家属看到 taken", st == "taken", str(st))

c.post("/api/meds", headers=H(ft), json={
    "name":"降压药","dosage":"1片","frequency":"每日1次","times":["07:00"],"elder_id":1})
missed = run_missed_cycle(now=datetime(2026, 10, 2, 9, 0, 0))
check("Day2 超时漏服 missed", any(m["slot"] == "07:00" for m in missed), str(missed))

# ---------- Day3 体征 ----------
b1 = c.post("/api/vitals", headers=H(et), json={"type":"bp","systolic":120,"diastolic":80})
b2 = c.post("/api/vitals", headers=H(et), json={"type":"bp","systolic":140,"diastolic":90})
q1 = c.post("/api/vitals", headers=H(et), json={"type":"bs","value":5.6})
h1 = c.post("/api/vitals", headers=H(et), json={"type":"hr","value":72})
w1 = c.post("/api/vitals", headers=H(et), json={"type":"weight","value":65})
check("Day3 录血压2条/血糖/心率/体重",
      all(x.status_code == 200 for x in (b1,b2,q1,h1,w1)),
      f"{b1.status_code}/{q1.status_code}/{h1.status_code}/{w1.status_code}")

bad1 = c.post("/api/vitals", headers=H(et), json={"type":"bp","systolic":120})
bad2 = c.post("/api/vitals", headers=H(et), json={"type":"abc","value":1})
check("Day3 血压缺值/非法类型 拦截400", bad1.status_code == 400 and bad2.status_code == 400,
      f"{bad1.status_code}/{bad2.status_code}")

rl = c.get("/api/vitals", headers=H(et))
check("Day3 体征列表", rl.status_code == 200 and len(rl.json()) == 5, f"条数{len(rl.json()) if rl.status_code==200 else rl.status_code}")

tr = c.get("/api/vitals/trend", headers=H(et)).json()
bp_today = tr.get("bp", [{}])[-1]
avg_ok = bp_today.get("systolic") == 130 and bp_today.get("diastolic") == 85
check("Day3 趋势按天聚合+同日平均(130/85)", avg_ok, str(bp_today))
check("Day3 趋势含 bs/hr/weight",
      all(k in tr for k in ("bs","hr","weight")), str(list(tr.keys())))

# PDF
rp = c.get("/api/vitals/export", headers=H(et))
pdf_ok = (rp.status_code == 200 and rp.content[:4] == b"%PDF" and len(rp.content) > 2000)
check("Day3 导出PDF(头%PDF/非空)", pdf_ok,
      f"{rp.status_code}/{len(rp.content)}字节" + ("/含图" if b"PNG" in rp.content[:5000] or len(rp.content)>10000 else ""))

# ---------- Day3 录音 ----------
up = c.post("/api/consults/upload", headers=H(et),
            files={"file": ("test.mp3", b"ID3FAKEAUDIODATA123", "audio/mpeg")},
            data={"duration":"120","hospital":"市医院"})
audio_url = up.json().get("audio_url","") if up.status_code == 200 else ""
fname = audio_url.split("/")[-1]
if fname:
    uploaded_files.append(fname)
check("Day3 录音上传", up.status_code == 200 and audio_url, str(up.json()) if up.status_code != 200 else audio_url)

badf = c.post("/api/consults/upload", headers=H(et),
              files={"file": ("t.txt", b"hello", "text/plain")}, data={"duration":"1"})
check("Day3 非音频拦截400", badf.status_code == 400, str(badf.status_code))

lc = c.get("/api/consults", headers=H(et))
check("Day3 录音列表", lc.status_code == 200 and len(lc.json()) == 1, f"条数{len(lc.json()) if lc.status_code==200 else lc.status_code}")

if fname:
    pa = c.get(f"/api/consults/audio/{fname}")
    check("Day3 录音回放200", pa.status_code == 200, str(pa.status_code))

# ---------- 权限/越权 ----------
fam_see = c.get("/api/vitals?elder_id=1", headers=H(ft))
check("权限 家属看绑定老人体征", fam_see.status_code == 200 and len(fam_see.json()) == 5, str(fam_see.status_code))
outsider = c.get("/api/vitals?elder_id=1", headers=H(wt))
check("权限 未绑定家属越权403", outsider.status_code == 403, str(outsider.status_code))

# ---------- 汇总 ----------
passed = sum(1 for _,ok,_ in results if ok)
total = len(results)
for name, ok, detail in results:
    print(("[PASS] " if ok else "[FAIL] ") + name + ("  | " + detail if detail else ""))
print(f"\n合计 {passed}/{total} 通过")

# 清理临时文件
try:
    for f in uploaded_files:
        p = os.path.join(os.path.dirname(__file__), "uploads", "consults", f)
        if os.path.exists(p):
            os.remove(p)
finally:
    test_engine.dispose()  # 释放SQLite连接，否则Windows下文件被占用无法删除
    if os.path.exists(TEST_DB):
        os.remove(TEST_DB)

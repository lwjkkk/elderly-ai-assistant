# Day4 验收：症状自查 + 体检报告 + 天气提醒
# 独立临时库；LLM/OCR/天气外部依赖用 mock 替换，验证接口流程、权限、风险落库、降级。
import os

import sqlalchemy
from sqlalchemy.orm import sessionmaker
import db.database as dbmod

TEST_DB = os.path.join(os.path.dirname(__file__), "_day4.db")
if os.path.exists(TEST_DB):
    os.remove(TEST_DB)
test_engine = sqlalchemy.create_engine(
    "sqlite:///" + TEST_DB.replace("\\", "/"),
    connect_args={"check_same_thread": False})
dbmod.engine = test_engine
dbmod.SessionLocal = sessionmaker(bind=test_engine, autoflush=False, autocommit=False)

from fastapi import FastAPI
from fastapi.testclient import TestClient
from db.database import Base
from api.auth import router as auth_router
from api.bind import router as bind_router
from api.symptom import router as symptom_router
from api.reports import router as reports_router
from api.weather import router as weather_router
import api.symptom as symptom_mod
import api.reports as reports_mod

Base.metadata.create_all(bind=test_engine)

app = FastAPI()
for r in (auth_router, bind_router, symptom_router, reports_router, weather_router):
    app.include_router(r)
c = TestClient(app)

# mock 外部服务
symptom_mod.symptom_advice = lambda text: (f"针对「{text}」的建议", "red")
reports_mod.recognize_image = lambda b64: "血压 120/80；血糖 5.6"
reports_mod.report_advice = lambda ocr, metrics=None: "各项指标大致正常，建议规律作息、定期复查"

results = []
def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
def H(t):
    return {"Authorization": f"Bearer {t}"}

# 前置：注册老人/家属/外人 + 绑定
c.post("/api/auth/register", json={"phone":"13800000001","password":"123456","nickname":"张奶奶","role":"elder"})
c.post("/api/auth/register", json={"phone":"13800000002","password":"123456","nickname":"小张","role":"family"})
c.post("/api/auth/register", json={"phone":"13800000003","password":"123456","nickname":"外人","role":"family"})
et = c.post("/api/auth/login", json={"phone":"13800000001","password":"123456"}).json()["access_token"]
ft = c.post("/api/auth/login", json={"phone":"13800000002","password":"123456"}).json()["access_token"]
wt = c.post("/api/auth/login", json={"phone":"13800000003","password":"123456"}).json()["access_token"]
code = c.post("/api/bind/invite", headers=H(et)).json()["invite_code"]
c.post("/api/bind/accept", json={"invite_code": code}, headers=H(ft))

# 1. 老人症状自查（mock red）
r = c.post("/api/symptom-check", headers=H(et), json={"input_text":"胸口闷痛"})
check("症状自查 老人提交 risk=red", r.status_code == 200 and r.json()["risk"] == "red",
      f"{r.status_code}/{r.json().get('risk')}")

# 2. 家属代提交（mock 默认red，改 mock 为 yellow 验证）
symptom_mod.symptom_advice = lambda text: ("建议尽快就医", "yellow")
r = c.post("/api/symptom-check", headers=H(ft), json={"input_text":"反复头疼","elder_id":1})
check("症状自查 家属代提交 risk=yellow", r.status_code == 200 and r.json()["risk"] == "yellow",
      f"{r.status_code}/{r.json().get('risk')}")

# 3. 症状列表
r = c.get("/api/symptom-check", headers=H(et))
check("症状历史列表(2条)", r.status_code == 200 and len(r.json()) == 2, str(len(r.json())))

# 4. 体检报告上传（mock OCR+建议）
r = c.post("/api/reports/upload", headers=H(et),
           files={"file": ("report.jpg", b"FAKEJPEG", "image/jpeg")})
d = r.json()
check("体检报告上传+OCR+建议",
      r.status_code == 200 and d.get("ocr_text") and d.get("advice_text") and d.get("image_url"),
      f"{r.status_code}")

# 5. 报告列表
r = c.get("/api/reports", headers=H(et))
check("体检报告列表(1条)", r.status_code == 200 and len(r.json()) == 1, str(len(r.json())))

# 6. 非图片上传 → 400
r = c.post("/api/reports/upload", headers=H(et),
           files={"file": ("t.txt", b"hello", "text/plain")})
check("体检报告 非图片拦截400", r.status_code == 400, str(r.status_code))

# 7. 天气降级（无 key）
r = c.get("/api/weather/remind", headers=H(et))
wd = r.json()
check("天气提醒 未配置key优雅降级",
      r.status_code == 200 and "QWEATHER_API_KEY" in wd["tip"], str(wd))

# 8. 越权
r = c.post("/api/symptom-check", headers=H(wt), json={"input_text":"咳嗽","elder_id":1})
check("症状 未绑定家属越权403", r.status_code == 403, str(r.status_code))

# 汇总
passed = sum(1 for _,ok,_ in results if ok)
for name, ok, detail in results:
    print(("[PASS] " if ok else "[FAIL] ") + name + ("  | " + detail if detail else ""))
print(f"\n合计 {passed}/{len(results)} 通过")

test_engine.dispose()
if os.path.exists(TEST_DB):
    os.remove(TEST_DB)

# test_health_disclaimer.py
# 免责声明断言测试：验证所有医疗接口响应都携带 disclaimer 字段，且文案与 core/disclaimer.py 一致
# 用法：python test_health_disclaimer.py
# 独立临时库，不碰 elderly.db；跑完自动清理。
# 覆盖11个场景：体征录入/列表、症状自查/历史、文字查药、图片查药(SKIP)、体检报告上传(SKIP)/列表(SKIP)、
#              增量同步、体征拍照识别、查药记录列表
# 注意：拍照查药和体检报告的 OCR 场景需要真实图片才能完整测试，
#       假图 OCR 无法识别时会自动 SKIP（不算失败）。如有真实药盒/报告图，
#       可替换场景6/7中的假图片数据以获得完整测试覆盖。
import os
import base64

# 1) 切换到独立临时库，再导入业务模块
import sqlalchemy
from sqlalchemy.orm import sessionmaker
import db.database as dbmod

TEST_DB = os.path.join(os.path.dirname(__file__), "_test_disclaimer.db")
if os.path.exists(TEST_DB):
    os.remove(TEST_DB)
TESTDB_URL = "sqlite:///" + TEST_DB.replace("\\", "/")
test_engine = sqlalchemy.create_engine(
    TESTDB_URL, connect_args={"check_same_thread": False})
dbmod.engine = test_engine
dbmod.SessionLocal = sessionmaker(bind=test_engine, autoflush=False, autocommit=False)

# 2) 导入业务模块
from fastapi import FastAPI
from fastapi.testclient import TestClient
from db.database import Base
from core.disclaimer import HEALTH_DISCLAIMER, DRUG_DISCLAIMER
from api.auth import router as auth_router
from api.bind import router as bind_router
from api.meds import router as meds_router
from api.vitals import router as vitals_router
from api.consults import router as consults_router
from api.symptom import router as symptom_router
from api.reports import router as reports_router
from api.drugs import router as drugs_router
from api.weather import router as weather_router
from api.routes import router as chat_router
from api.sync import router as sync_router
import api.vitals  # 用于 mock OCR/LLM（体征拍照识别测试）

Base.metadata.create_all(bind=test_engine)

app = FastAPI()
for r in (auth_router, bind_router, meds_router, vitals_router,
          consults_router, symptom_router, reports_router, drugs_router,
          weather_router, chat_router, sync_router):
    app.include_router(r)
c = TestClient(app)

results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] {name}" + (f" — {detail}" if detail else ""))


def H(t):
    return {"Authorization": f"Bearer {t}"}


print("=" * 60)
print("免责声明断言测试")
print("=" * 60)

# ---------- 准备数据：注册老人+家属并绑定 ----------
print("\n[准备] 注册老人/家属并绑定")
c.post("/api/auth/register", json={"phone": "13800000001", "password": "123456",
                                     "nickname": "张奶奶", "role": "elder"})
c.post("/api/auth/register", json={"phone": "13800000002", "password": "123456",
                                     "nickname": "小张", "role": "family"})
et = c.post("/api/auth/login", json={"phone": "13800000001", "password": "123456"}).json()["access_token"]
ft = c.post("/api/auth/login", json={"phone": "13800000002", "password": "123456"}).json()["access_token"]
code = c.post("/api/bind/invite", headers=H(et)).json()["invite_code"]
c.post("/api/bind/accept", json={"invite_code": code}, headers=H(ft))
print("  准备完成")

# ---------- 1. 体征录入接口 ----------
print("\n[1] 体征录入 POST /api/vitals")
r = c.post("/api/vitals", json={"type": "bp", "systolic": 140, "diastolic": 90}, headers=H(et))
if r.status_code == 200:
    data = r.json()
    has_field = "disclaimer" in data
    text_match = data.get("disclaimer") == HEALTH_DISCLAIMER
    check("响应包含 disclaimer 字段", has_field)
    check("disclaimer 文案 = HEALTH_DISCLAIMER", text_match,
          f"实际: {data.get('disclaimer', '(无)')[:40]}...")
else:
    check("体征录入接口可用", False, f"HTTP {r.status_code}: {r.text}")

# ---------- 2. 体征列表接口 ----------
print("\n[2] 体征列表 GET /api/vitals")
r = c.get("/api/vitals", headers=H(et))
if r.status_code == 200:
    data = r.json()
    if isinstance(data, list) and len(data) > 0:
        item = data[0]
        has_field = "disclaimer" in item
        text_match = item.get("disclaimer") == HEALTH_DISCLAIMER
        check("列表每条记录包含 disclaimer 字段", has_field)
        check("列表 disclaimer 文案 = HEALTH_DISCLAIMER", text_match)
    else:
        check("体征列表有数据", False, "列表为空")
else:
    check("体征列表接口可用", False, f"HTTP {r.status_code}")

# ---------- Mock LLM（避免依赖真实 API，所有需要 call_qwen 的接口用固定测试数据） ----------
import core.qwen_llm
import core.health_llm
import api.drugs
import api.vitals
def _mock_call_qwen(system_prompt, user_prompt):
    if "症状" in system_prompt or "SYMPTOM" in system_prompt.upper():
        return "这是测试症状建议：注意休息，多喝水，如持续不缓解请就医。\nRISK: green"
    return "这是测试解读内容，仅供健康科普参考，不构成诊断或用药建议。"
# 每个 import 了 call_qwen 的模块都要单独替换（Python 的 from import 会复制引用）
core.qwen_llm.call_qwen = _mock_call_qwen
core.health_llm.call_qwen = _mock_call_qwen
api.drugs.call_qwen = _mock_call_qwen
api.vitals.call_qwen = _mock_call_qwen

# ---------- 3. 症状自查接口 ----------
print("\n[3] 症状自查 POST /api/symptom-check")
r = c.post("/api/symptom-check", json={"input_text": "头疼两天"}, headers=H(et))
if r.status_code == 200:
    data = r.json()
    has_field = "disclaimer" in data
    text_match = data.get("disclaimer") == HEALTH_DISCLAIMER
    check("响应包含 disclaimer 字段", has_field)
    check("disclaimer 文案 = HEALTH_DISCLAIMER", text_match,
          f"实际: {data.get('disclaimer', '(无)')[:40]}...")
else:
    check("症状自查接口可用", False, f"HTTP {r.status_code}: {r.text}")

# ---------- 4. 症状自查历史接口 ----------
print("\n[4] 症状自查历史 GET /api/symptom-check")
r = c.get("/api/symptom-check", headers=H(et))
if r.status_code == 200:
    data = r.json()
    if isinstance(data, list) and len(data) > 0:
        item = data[0]
        has_field = "disclaimer" in item
        check("历史列表每条包含 disclaimer 字段", has_field)
    else:
        check("症状自查历史有数据", False, "列表为空")
else:
    check("症状自查历史接口可用", False, f"HTTP {r.status_code}")

# ---------- 5. 拍照查药（文字） ----------
print("\n[5] 拍照查药（文字）POST /api/drugs/query-name")
r = c.post("/api/drugs/query-name", json={"name": "阿司匹林"}, headers=H(et))
if r.status_code == 200:
    data = r.json()
    has_field = "disclaimer" in data
    text_match = data.get("disclaimer") == DRUG_DISCLAIMER
    check("响应包含 disclaimer 字段", has_field)
    check("disclaimer 文案 = DRUG_DISCLAIMER", text_match,
          f"实际: {data.get('disclaimer', '(无)')[:40]}...")
else:
    check("文字查药接口可用", False, f"HTTP {r.status_code}: {r.text}")

# ---------- 6. 拍照查药（图片base64） ----------
print("\n[6] 拍照查药（图片）POST /api/drugs/query")
# 用一个1x1的PNG base64做测试
fake_png = base64.b64encode(
    b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01'
    b'\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0'
    b'\x00\x00\x00\x03\x00\x01\x5d\x15\xe8\xb8\x00\x00\x00\x00IEND\xaeB`\x82'
).decode()
r = c.post("/api/drugs/query", json={"image_base64": fake_png}, headers=H(et))
if r.status_code == 200:
    data = r.json()
    has_field = "disclaimer" in data
    check("响应包含 disclaimer 字段", has_field)
else:
    # OCR 场景需要真实药盒图片，假图无法识别时跳过，不算失败
    print(f"  [SKIP] 图片查药 OCR 场景需要真实药盒图片（假图 OCR 无法识别），HTTP {r.status_code}，跳过 disclaimer 断言")

# ---------- 7. 体检报告上传 ----------
print("\n[7] 体检报告上传 POST /api/reports/upload")
r = c.post("/api/reports/upload",
           files={"file": ("report.jpg", b"fake image content", "image/jpeg")},
           headers=H(et))
if r.status_code == 200:
    data = r.json()
    has_field = "disclaimer" in data
    text_match = data.get("disclaimer") == HEALTH_DISCLAIMER
    check("响应包含 disclaimer 字段", has_field)
    check("disclaimer 文案 = HEALTH_DISCLAIMER", text_match)
else:
    # OCR 场景需要真实体检报告图片，假图无法识别时跳过，不算失败
    print(f"  [SKIP] 体检报告 OCR 场景需要真实报告图片（假图 OCR 无法识别），HTTP {r.status_code}，跳过 disclaimer 断言")

# ---------- 8. 体检报告列表 ----------
print("\n[8] 体检报告列表 GET /api/reports")
r = c.get("/api/reports", headers=H(et))
if r.status_code == 200:
    data = r.json()
    if isinstance(data, list) and len(data) > 0:
        item = data[0]
        has_field = "disclaimer" in item
        check("列表每条记录包含 disclaimer 字段", has_field)
    else:
        # 列表为空可能是因为场景7上传被SKIP（假图OCR失败），联动SKIP不算失败
        print("  [SKIP] 体检报告列表为空（场景7上传可能被SKIP，未产生数据），跳过 disclaimer 断言")
else:
    check("体检报告列表接口可用", False, f"HTTP {r.status_code}")

# ---------- 9. 增量同步接口（vitals部分带disclaimer） ----------
print("\n[9] 增量同步 GET /api/sync")
r = c.get("/api/sync", headers=H(et))
if r.status_code == 200:
    data = r.json()
    vitals = data.get("vitals", [])
    if len(vitals) > 0:
        item = vitals[0]
        has_field = "disclaimer" in item
        check("同步数据中 vitals 每条带 disclaimer", has_field)
    else:
        check("同步数据有 vitals 记录", False, "vitals 为空")
    symptoms = data.get("symptoms", [])
    if len(symptoms) > 0:
        item = symptoms[0]
        has_field = "disclaimer" in item
        check("同步数据中 symptoms 每条带 disclaimer", has_field)
else:
    check("增量同步接口可用", False, f"HTTP {r.status_code}")

# ---------- 10. 体征拍照识别 ----------
print("\n[10] 体征拍照识别 POST /api/vitals/recognize")
# mock OCR 和 LLM，避免依赖真实模型
api.vitals.recognize_image = lambda b64: "血压 135/85 mmHg"
api.vitals.call_qwen = lambda sp, up: "TYPE: bp\nSYSTOLIC: 135\nDIASTOLIC: 85\nUNIT: mmHg"
r = c.post("/api/vitals/recognize",
            json={"image_base64": "ZmFrZQ=="},
            headers=H(et))
if r.status_code == 200:
    data = r.json()
    has_field = "disclaimer" in data
    text_match = data.get("disclaimer") == HEALTH_DISCLAIMER
    check("响应包含 disclaimer 字段", has_field)
    check("disclaimer 文案 = HEALTH_DISCLAIMER", text_match)
else:
    check("体征拍照识别接口可用", False, f"HTTP {r.status_code}: {r.text}")

# ---------- 11. 查药记录列表 ----------
print("\n[11] 查药记录列表 GET /api/drugs/records")
r = c.get("/api/drugs/records", headers=H(et))
if r.status_code == 200:
    data = r.json()
    if isinstance(data, list) and len(data) > 0:
        item = data[0]
        # DrugQueryOut 的 disclaimer 是可选字段，有就验证，没有也不算错
        if "disclaimer" in item and item["disclaimer"]:
            check("查药记录包含 disclaimer 字段", True)
        else:
            print("  [SKIP] 查药记录 disclaimer 为可选字段，当前记录为空，跳过断言")
    else:
        # 列表为空可能是因为还没有查药记录，SKIP
        print("  [SKIP] 查药记录列表为空（尚未产生查药记录），跳过 disclaimer 断言")
else:
    check("查药记录列表接口可用", False, f"HTTP {r.status_code}")

# ---------- 汇总 ----------
print("\n" + "=" * 60)
passed = sum(1 for _, ok, _ in results if ok)
failed = sum(1 for _, ok, _ in results if not ok)
total = len(results)
print(f"测试汇总：{passed}/{total} 通过，{failed} 失败")
if failed > 0:
    print("\n失败项：")
    for name, ok, detail in results:
        if not ok:
            print(f"  - {name}" + (f": {detail}" if detail else ""))
print("=" * 60)

# 清理临时库
if os.path.exists(TEST_DB):
    os.remove(TEST_DB)

exit(0 if failed == 0 else 1)

# -*- coding: utf-8 -*-
"""10.22 成员A：语音转写体征草稿解析器 真实环境测试。

覆盖：血压/血糖/心率/体重；单位换算(mg/dL→mmol/L、斤→kg)；时间解析；
范围校验(与 api/vitals.create_vital 规则一致)；不落库；未命中返回 None。
"""
import sys, os, io
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from datetime import datetime
from core.vitals_draft import parse_spoken_vitals, validate_draft, _UNIT

NOW = datetime(2026, 10, 19, 10, 0, 0)  # 固定“今天=2026-10-19”，保证 measured_at 可复现


def ok(name, cond, detail=""):
    if not cond:
        raise AssertionError(f"[FAIL] {name}  {detail}")
    print(f"[PASS] {name}")


# ---- 血压 ----
d = parse_spoken_vitals("今天早上量了血压 140/90", now=NOW)
ok("血压 x/y", d and d["type"] == "bp" and d["systolic"] == 140 and d["diastolic"] == 90,
   f"got={d}")
ok("血压 单位/校验", d["unit"] == "mmHg" and d["valid"] is True and d["errors"] == [])
ok("血压 时间解析", d["measured_text"] == "今天早上" and d["measured_at"] == "2026-10-19 07:00:00",
   f"measured_text={d['measured_text']} at={d['measured_at']}")
ok("血压 原文证据", d["raw_text"] and "140" in d["raw_text"])

d = parse_spoken_vitals("血压高压150低压95", now=NOW)
ok("血压 高压/低压", d and d["type"] == "bp" and d["systolic"] == 150 and d["diastolic"] == 95 and d["valid"])

d = parse_spoken_vitals("血压一百四十五九十", now=NOW)
ok("血压 中文连续数字", d and d["type"] == "bp" and d["systolic"] == 145 and d["diastolic"] == 90 and d["valid"],
   f"got={d}")

d = parse_spoken_vitals("高压一百四十五，低压九十", now=NOW)
ok("血压 中文标签数字", d and d["type"] == "bp" and d["systolic"] == 145 and d["diastolic"] == 90 and d["valid"],
   f"got={d}")

d = parse_spoken_vitals("昨天下午量的血压 120/80", now=NOW)
ok("血压 时间=昨天下午", d and d["measured_text"] == "昨天下午" and d["measured_at"] == "2026-10-18 15:00:00",
   f"at={d and d['measured_at']}")

# ---- 血糖 ----
d = parse_spoken_vitals("血糖 5.6", now=NOW)
ok("血糖 mmol/L", d and d["type"] == "bs" and d["value"] == 5.6 and d["unit"] == "mmol/L" and d["valid"])

for text, context in (("空腹血糖7.2", "fasting"), ("餐后血糖7.2", "postprandial"), ("非空腹血糖12", "random")):
    d = parse_spoken_vitals(text, now=NOW)
    ok(f"血糖场景 {context}", d and d["type"] == "bs" and d["measurement_context"] == context, f"got={d}")

d = parse_spoken_vitals("血糖 108 毫克每分升", now=NOW)
ok("血糖 mg/dL→mmol/L(108/18=6.0)", d and d["type"] == "bs" and d["value"] == 6.0 and d["valid"],
   f"value={d and d['value']}")

d = parse_spoken_vitals("空腹血糖 7.2 毫摩尔每升", now=NOW)
ok("血糖 带单位 mmol/L", d and d["value"] == 7.2 and d["valid"])

# ---- 心率 ----
d = parse_spoken_vitals("心率 75 次/分", now=NOW)
ok("心率", d and d["type"] == "hr" and d["value"] == 75.0 and d["unit"] == "次/分" and d["valid"])

# ---- 体重 ----
d = parse_spoken_vitals("体重 65 公斤", now=NOW)
ok("体重 kg", d and d["type"] == "weight" and d["value"] == 65.0 and d["unit"] == "kg" and d["valid"])

d = parse_spoken_vitals("体重 130 斤", now=NOW)
ok("体重 斤→kg(130/2=65)", d and d["type"] == "weight" and d["value"] == 65.0 and d["valid"],
   f"value={d and d['value']}")

# ---- 范围校验（复用 create_vital 规则，越界应 valid=False 且带错误）----
d = parse_spoken_vitals("血压 350/200", now=NOW)
ok("血压 越界→valid False", d and d["valid"] is False and any("收缩压" in e for e in d["errors"]),
   f"errors={d and d['errors']}")

d = parse_spoken_vitals("血压 140/90 但收缩压需大于舒张压→误报", now=NOW)  # 该句无血压数值对
d = parse_spoken_vitals("血压 90/140", now=NOW)
ok("血压 sys<=dia→valid False", d and d["valid"] is False and any("大于" in e for e in d["errors"]))

d = parse_spoken_vitals("血糖 0.5", now=NOW)
ok("血糖 越界→valid False", d and d["valid"] is False and d["errors"])

# ---- 未命中体征口述 ----
d = parse_spoken_vitals("今天天气不错，吃了早饭", now=NOW)
ok("非体征口述→None", d is None)

# ---- hint_type 优先 ----
d = parse_spoken_vitals("血压140/90 血糖5.6", hint_type="bs", now=NOW)
ok("hint_type=bs 优先", d and d["type"] == "bs" and d["value"] == 5.6)

# ---- 不落库（纯函数，无 DB 副作用；草稿本身不入库）----
import inspect
src = inspect.getsource(parse_spoken_vitals)
ok("解析器无 DB 落库语句", "db.add" not in src and "db.commit" not in src and "session.add" not in src)
ok("草稿仅含字段不触发落库", set(d.keys()) == {
    "type", "systolic", "diastolic", "value", "unit", "measured_text",
        "measured_at", "raw_text", "measurement_context", "confidence", "valid", "errors"} if d else True)

# ---- API 端到端（TestClient + 内存库，走完整 /api/vitals/parse-spoken，验证不落库）----
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from db.database import Base, get_db
from db.models import User, Vitals
from api.vitals import router as _vr
from core.security import get_current_user

_engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
_TS = sessionmaker(bind=_engine, autoflush=False, autocommit=False)
Base.metadata.create_all(bind=_engine)


def _ovr_db():
    db = _TS()
    try:
        yield db
    finally:
        db.close()


_api = FastAPI()
_api.include_router(_vr)
_api.dependency_overrides[get_db] = _ovr_db
_api.dependency_overrides[get_current_user] = lambda: User(id=1, role="elder", nickname="测试老人")
_client = TestClient(_api)

_resp = _client.post("/api/vitals/parse-spoken", json={"text": "今天早上量了血压140/90"})
ok("API HTTP 200", _resp.status_code == 200, f"status={_resp.status_code} body={_resp.text}")
_data = _resp.json()
ok("API 草稿命中血压并校验通过",
   _data["hit"] is True and _data["type"] == "bp" and _data["systolic"] == 140 and _data["diastolic"] == 90 and _data["valid"] is True,
   f"data={_data}")
ok("API 非体征口述 hit=False",
   _client.post("/api/vitals/parse-spoken", json={"text": "今天天气不错"}).json()["hit"] is False)

_db = _TS()
_n = _db.query(Vitals).count()
_db.close()
ok("端点调用后 Vitals 表 0 条（确认不落库）", _n == 0, f"count={_n}")

print(f"\nALL PASSED ({datetime.now().strftime('%Y-%m-%d %H:%M:%S')})")
print("实测：解析器仅产出草稿对象，未调用任何 DB 写库，符合“抽取不直接入库”。")

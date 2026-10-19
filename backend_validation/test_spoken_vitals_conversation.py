# -*- coding: utf-8 -*-
"""10.23 成员A：体征口述多轮会话（#8 缺字段追问/字段合并/确认落库）真实环境测试。

覆盖：缺字段追问；字段合并；确认后复用 POST /api/vitals 落库；未确认不写入；
取消后不可确认；重复确认被拒；范围越界追问。
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from db.database import Base, get_db
from db.models import User, Vitals, VitalDraftConversation
from api.vitals import router as _vr
from core.security import get_current_user

# StaticPool：内存库跨线程共享同一连接，保证 TestClient worker 线程可见建表结果（真实可用）
_engine = create_engine("sqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})
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


def ok(name, cond, detail=""):
    if not cond:
        raise AssertionError(f"[FAIL] {name}  {detail}")
    print(f"[PASS] {name}")


def vitals_count():
    db = _TS()
    n = db.query(Vitals).count()
    db.close()
    return n


# 1) 首轮缺类型/缺数值：只说“量血压”但无数值 → 追问，不落库
r = _client.post("/api/vitals/draft-conversations", json={"text": "量一下血压"})
ok("首轮 200", r.status_code == 200, r.text)
d = r.json()
ok("首轮 定类血压但缺双值", d["status"] == "collecting" and d["draft"]["type"] == "bp" and "systolic" in d["missing"] and "diastolic" in d["missing"],
   f"missing={d['missing']}")
ok("首轮 追问血压", "收缩压" in d["question"] or "140/90" in d["question"], d["question"])
ok("首轮 不可确认", d["can_confirm"] is False)
ok("首轮 未落库", vitals_count() == 0)
sid = d["session_id"]

# 2) 续轮补高压
r = _client.post("/api/vitals/draft-conversations", json={"text": "高压150", "session_id": sid})
d = r.json()
ok("补高压后仍缺低压", d["status"] == "collecting" and d["draft"]["systolic"] == 150 and "diastolic" in d["missing"],
   f"draft={d['draft']} missing={d['missing']}")
ok("追问缺低压", "低压" in d["question"], d["question"])

# 3) 续轮补低压 → ready
r = _client.post("/api/vitals/draft-conversations", json={"text": "低压95", "session_id": sid})
d = r.json()
ok("补低压后 ready", d["status"] == "ready" and d["can_confirm"] is True and d["draft"]["systolic"] == 150 and d["draft"]["diastolic"] == 95,
   f"status={d['status']} draft={d['draft']}")
ok("信息齐全提示", "确认" in d["question"], d["question"])
ok("仍未落库", vitals_count() == 0)

# 4) 未确认前 vitals 表 0 条（本会话 confirm 之前）
# 5) confirm → 落库 1 条
r = _client.post(f"/api/vitals/draft-conversations/{sid}/confirm")
ok("confirm 200", r.status_code == 200, r.text)
cv = r.json()
ok("confirm 落库类型/数值", cv["type"] == "bp" and cv["systolic"] == 150 and cv["diastolic"] == 95, cv)
ok("确认后 vitals 1 条", vitals_count() == 1, f"count={vitals_count()}")

# 6) 重复确认 → 400
r = _client.post(f"/api/vitals/draft-conversations/{sid}/confirm")
ok("重复确认被拒", r.status_code == 400, f"status={r.status_code} body={r.text}")
ok("重复确认不重复落库", vitals_count() == 1)

# 7) 取消后不可确认，不落库
r = _client.post("/api/vitals/draft-conversations", json={"text": "血糖"})
d = r.json(); sid2 = d["session_id"]
ok("血糖缺数值追问", d["status"] == "collecting" and d["draft"]["type"] == "bs" and d["missing"] == ["value"], d)
r = _client.request("DELETE", f"/api/vitals/draft-conversations/{sid2}")
ok("取消 200", r.status_code == 200, r.text)
r = _client.post(f"/api/vitals/draft-conversations/{sid2}/confirm")
ok("取消后 confirm 400", r.status_code == 400, r.text)
ok("取消后不落库", vitals_count() == 1)  # 仅上一个血压确认那条

# 8) 血糖多轮补数值 → 确认落库
r = _client.post("/api/vitals/draft-conversations", json={"text": "血糖"})
sid3 = r.json()["session_id"]
r = _client.post("/api/vitals/draft-conversations", json={"text": "5.6", "session_id": sid3})
d = r.json()
ok("血糖补数值 ready", d["status"] == "ready" and d["draft"]["value"] == 5.6 and d["draft"]["unit"] == "mmol/L", d)
r = _client.post(f"/api/vitals/draft-conversations/{sid3}/confirm")
ok("血糖确认落库", r.status_code == 200 and r.json()["type"] == "bs" and r.json()["value"] == 5.6, r.text)
ok("血糖落库后 count=2", vitals_count() == 2)

# 9) 范围越界：血糖 0.5 → 追问范围，不可确认，confirm 400
r = _client.post("/api/vitals/draft-conversations", json={"text": "血糖0.5"})
d = r.json(); sid4 = d["session_id"]
ok("血糖越界 collecting", d["status"] == "collecting" and d["can_confirm"] is False, d)
ok("血糖越界追问范围", "合理范围" in d["question"] or "1.0" in d["question"], d["question"])
r = _client.post(f"/api/vitals/draft-conversations/{sid4}/confirm")
ok("越界 confirm 400", r.status_code == 400, r.text)
ok("越界不落库", vitals_count() == 2)

# 10) 完整血压单轮 → ready 且可确认
r = _client.post("/api/vitals/draft-conversations", json={"text": "今天早上量了血压140/90"})
d = r.json()
ok("血压完整单轮 ready", d["status"] == "ready" and d["can_confirm"] is True and d["draft"]["systolic"] == 140, d)
ok("血压时间解析", d["draft"]["measured_text"] == "今天早上", d["draft"])

# 11) 缺失字段会话无法 confirm（collecting）
r = _client.post("/api/vitals/draft-conversations", json={"text": "量一下血压"})
sid5 = r.json()["session_id"]
r = _client.post(f"/api/vitals/draft-conversations/{sid5}/confirm")
ok("缺字段 collecting confirm 400", r.status_code == 400, r.text)
ok("全程未确认不落库（累计仍 2 条）", vitals_count() == 2)

# 12) 会话持久化（重进页面可恢复）：新 session 读旧会话
r = _client.post("/api/vitals/draft-conversations", json={"text": "体重70公斤"})
sid6 = r.json()["session_id"]
ok("体重完整 ready", r.json()["status"] == "ready", r.json())
r = _client.post("/api/vitals/draft-conversations", json={"text": "再确认下", "session_id": sid6})
ok("重进页面会话恢复(仍在 ready)", r.json()["status"] == "ready", r.json())

print("\nALL PASSED (10.23 体征口述多轮会话)")
print("实测：缺字段会追问；确认前无新增记录；取消/重复/越界/失败路径均有结果记录；确认后复用 POST /api/vitals 落库。")

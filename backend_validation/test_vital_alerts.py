# -*- coding: utf-8 -*-
"""10.27 #9 血压/血糖异常阈值 + 可追踪事件 + 用药提前打卡 真实环境测试。"""
import os
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import Depends
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from db.database import Base, get_db
from db.models import User, FamilyBinding, Vitals, Medication, VitalAlert
from core.security import get_current_user
from core import vital_thresholds as vth
from services import push as push_svc

PASS, FAIL = [], []
_engine = create_engine("sqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})
_TS = sessionmaker(bind=_engine, autoflush=False, expire_on_commit=False)
Base.metadata.create_all(bind=_engine)
_cur = None


def ok(name, cond, detail=""):
    if cond:
        PASS.append(name); print(f"[PASS] {name}" + (f"  {detail}" if detail else ""))
    else:
        FAIL.append(name); print(f"[FAIL] {name}  {detail}")


def make_app():
    from api.vitals import router as vitals_r
    from api.meds import router as meds_r
    from fastapi import FastAPI
    app = FastAPI()
    for r in (vitals_r, meds_r):
        app.include_router(r)

    def _get_db():
        db = _TS()
        try:
            yield db
        finally:
            db.close()
    app.dependency_overrides[get_db] = _get_db

    def _current_user(db=Depends(get_db)):
        if _cur is None:
            return None
        return db.merge(_cur)
    app.dependency_overrides[get_current_user] = _current_user
    return app


app = make_app()
client = TestClient(app)
push_svc.clear_sent()


def seed():
    db = _TS()
    elder = User(phone="13800000008", nickname="老人", password_hash="x", role="elder")
    free = User(phone="13800000009", nickname="未绑家属", password_hash="x", role="family")
    bound = User(phone="13800000010", nickname="已绑家属", password_hash="x", role="family")
    db.add_all([elder, free, bound]); db.commit()
    db.refresh(elder); db.refresh(free); db.refresh(bound)
    db.add(FamilyBinding(elder_id=elder.id, family_id=bound.id, status="active", invite_code="XYZ123"))
    med = Medication(elder_id=elder.id, created_by=elder.id, name="阿司匹林",
                     dosage="1片", frequency="每日1次", times=["09:00"],
                     start_date=date.today().isoformat())
    db.add(med); db.commit(); db.refresh(med)
    return elder, free, bound, med


elder, free, bound, med = seed()


def set_cur(u):
    global _cur
    _cur = u


def main():
    # ---- 1. 阈值边界 ----
    e = vth.evaluate_bp
    ok("血压 140/90 → high", e(140, 90)["level"] == "high")
    ok("血压 139/89 → 不异常", e(139, 89)["abnormal"] is False)
    ok("血压 150/95 → high", e(150, 95)["level"] == "high")
    ok("血压 89/65 → low", e(89, 65)["level"] == "low")
    ok("血压 95/55 → low", e(95, 55)["level"] == "low")
    ok("血压 150/55 → mixed", e(150, 55)["level"] == "mixed")
    ok("血压 90/60 → 不异常", e(90, 60)["abnormal"] is False)
    ok("血压 128/82 → 不异常", e(128, 82)["abnormal"] is False)
    ok("空腹血糖 7.0 → high", vth.evaluate_bs(7.0, "fasting")["level"] == "high")
    ok("餐后血糖 7.2 → 不套空腹高值阈值", vth.evaluate_bs(7.2, "postprandial")["abnormal"] is False)
    ok("未注明血糖 7.2 → 不套空腹高值阈值", vth.evaluate_bs(7.2, "unknown")["abnormal"] is False)
    ok("血糖 6.1 → 不异常", vth.evaluate_bs(6.1)["abnormal"] is False)
    ok("血糖 3.9 → 不异常", vth.evaluate_bs(3.9)["abnormal"] is False)
    ok("血糖 3.8 → low", vth.evaluate_bs(3.8)["level"] == "low")
    ok("空腹血糖 12 → high", vth.evaluate_bs(12.0, "fasting")["level"] == "high")
    ok("心率/体重 → 不判异常", vth.evaluate("hr", value=80) is None and vth.evaluate("weight", value=60) is None)

    # ---- 2. POST 血压异常 → 事件 + 推送 ----
    set_cur(elder)
    r = client.post("/api/vitals", json={"type": "bp", "systolic": 150, "diastolic": 95,
                                         "measured_at": "2026-10-19T09:00:00"})
    ok("POST 血压150/95 → 200", r.status_code == 200, f"status={r.status_code} body={r.text[:60]}")
    sent = push_svc.get_sent()
    ok("推送: 已绑定家属收到体征异常提醒", any(n.get("receiver_id") == bound.id and "体征异常" in n.get("title", "")
                                           for n in sent), f"sent={len(sent)}")

    # ---- 3. POST 血糖异常 → 事件 ----
    set_cur(elder)
    r = client.post("/api/vitals", json={"type": "bs", "value": 3.5, "measured_at": "2026-10-19T09:10:00"})
    ok("POST 血糖3.5 → 200", r.status_code == 200, f"status={r.status_code}")

    # ---- 4. POST 正常体征 → 无新事件 ----
    set_cur(elder)
    before = len(client.get("/api/vitals/alerts").json())
    client.post("/api/vitals", json={"type": "bp", "systolic": 128, "diastolic": 82,
                                     "measured_at": "2026-10-19T10:00:00"})
    after = len(client.get("/api/vitals/alerts").json())
    ok("正常血压128/82 → 不产生新事件", after == before, f"before={before} after={after}")

    # ---- 5. 事件读取授权 ----
    set_cur(elder)
    r = client.get("/api/vitals/alerts")
    al = r.json()
    ok("事件: 老人本人可见(≥2条)", r.status_code == 200 and len(al) >= 2, f"n={len(al)}")
    ok("事件: 含血压high与血糖low", {"bp": "high", "bs": "low"} and
       any(a["vital_type"] == "bp" and a["level"] == "high" for a in al)
       and any(a["vital_type"] == "bs" and a["level"] == "low" for a in al),
       f"levels={[a['vital_type']+':'+a['level'] for a in al]}")
    set_cur(bound)
    r = client.get("/api/vitals/alerts", params={"elder_id": elder.id})
    ok("事件: 已绑定家属可见", r.status_code == 200 and len(r.json()) >= 2, f"n={len(r.json())}")
    set_cur(free)
    r = client.get("/api/vitals/alerts", params={"elder_id": elder.id})
    ok("事件: 未绑定家属 403", r.status_code == 403, f"status={r.status_code}")

    # ---- 6. 用药提前打卡回归（后端拒绝）----
    set_cur(elder)
    tomorrow = (date.today() + timedelta(days=1)).isoformat()
    r = client.post("/api/meds/checkin", json={"medication_id": med.id, "slot": "09:00", "date": tomorrow})
    ok("用药: 提前打卡(未来日期) → 400 拒绝", r.status_code == 400
       and "尚未到" in r.json().get("detail", ""), f"status={r.status_code} body={r.text[:60]}")

    print("\n==== RESULT ====")
    print(f"PASS={len(PASS)} FAIL={len(FAIL)}  (10.27 血压/血糖异常阈值+事件+用药回归)")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()

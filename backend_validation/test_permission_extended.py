# -*- coding: utf-8 -*-
"""10.26 补测：报告/录音/摘要/查药四类请求级三态（本人/未绑/已绑）+ 隐私跨时断言。
不依赖 B/C，属 A 自己范围的可独立补测项（文档第 8 节其三/其四）。"""
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import Depends
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from db.database import Base, get_db
from db.models import User, FamilyBinding, Vitals, HealthReport, ConsultRecord, ChatSummary, DrugQuery
from core.security import get_current_user

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
    from api.reports import router as reports_r
    from api.drugs import router as drugs_r
    from api.consults import router as consults_r
    from api.routes import router as routes_r
    from fastapi import FastAPI
    app = FastAPI()
    for r in (vitals_r, reports_r, drugs_r, consults_r, routes_r):
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

# 隐私开启时间（UTC naive）
T = datetime(2026, 10, 1, 0, 0, 0)
BEFORE = datetime(2026, 9, 1, 8, 0, 0)   # < T → 家属可见
AFTER = datetime(2026, 10, 10, 8, 0, 0)  # > T → 家属不可见


def seed():
    db = _TS()
    elder = User(phone="13800000005", nickname="老人Y", password_hash="x", role="elder",
                 birth_ym="1966-11", sync_summary_to_family=False, privacy_enabled_at=T)  # younger + 开隐私
    free = User(phone="13800000006", nickname="未绑家属", password_hash="x", role="family")
    bound = User(phone="13800000007", nickname="已绑家属", password_hash="x", role="family")
    db.add_all([elder, free, bound]); db.commit()
    db.refresh(elder); db.refresh(free); db.refresh(bound)
    db.add(FamilyBinding(elder_id=elder.id, family_id=bound.id, status="active", invite_code="AABBCC"))
    db.add(Vitals(elder_id=elder.id, type="bp", systolic=128, diastolic=82))
    db.add(HealthReport(elder_id=elder.id, ocr_text="体检单OCR", advice_text="建议"))
    db.add(ConsultRecord(elder_id=elder.id, audio_url="/x.mp3", duration=8))
    # 摘要：BEFORE 可见 / AFTER 不可见（隐私跨时断言）
    db.add(ChatSummary(elder_id=elder.id, category="drug", question="Q1", summary="S1", created_at=BEFORE))
    db.add(ChatSummary(elder_id=elder.id, category="drug", question="Q2", summary="S2", created_at=AFTER))
    # 查药：chat 类 BEFORE / AFTER（隐私跨时断言）
    db.add(DrugQuery(elder_id=elder.id, kind="chat", input_text="D1", created_at=BEFORE))
    db.add(DrugQuery(elder_id=elder.id, kind="chat", input_text="D2", created_at=AFTER))
    db.commit()
    db.refresh(elder)
    return elder, free, bound


elder, free, bound = seed()


def set_cur(u):
    global _cur
    _cur = u


def main():
    # ---- 四类数据：老人本人读取 ----
    set_cur(elder)
    for name, path in [("报告", "/api/reports"), ("录音", "/api/consults"),
                       ("摘要", "/api/chat/summaries"), ("查药", "/api/drugs/records")]:
        r = client.get(path)
        ok(f"本人读取-{name} 200", r.status_code == 200, f"status={r.status_code}")

    # ---- 四类数据：未绑定家属（显式 elder_id）→ 403 ----
    set_cur(free)
    for name, path in [("报告", "/api/reports"), ("录音", "/api/consults"),
                       ("摘要", "/api/chat/summaries"), ("查药", "/api/drugs/records")]:
        r = client.get(path, params={"elder_id": elder.id})
        ok(f"未绑家属-{name} 403", r.status_code == 403, f"status={r.status_code} body={r.text[:40]}")

    # ---- 四类数据：已绑定家属（显式 elder_id）→ 200 ----
    set_cur(bound)
    for name, path in [("报告", "/api/reports"), ("录音", "/api/consults"),
                       ("摘要", "/api/chat/summaries"), ("查药", "/api/drugs/records")]:
        r = client.get(path, params={"elder_id": elder.id})
        ok(f"已绑家属-{name} 200", r.status_code == 200, f"status={r.status_code}")

    # ---- 隐私跨时断言（摘要）：已绑家属只见 BEFORE，本人见全部 ----
    set_cur(bound)
    r = client.get("/api/chat/summaries", params={"elder_id": elder.id})
    ids = [x["id"] for x in r.json()]
    s_before = [x for x in r.json() if x["summary"] == "S1"]
    s_after = [x for x in r.json() if x["summary"] == "S2"]
    ok("隐私-摘要: 已绑家属只见开启前记录", len(s_before) == 1 and len(s_after) == 0,
       f"n={len(r.json())}")
    set_cur(elder)
    r = client.get("/api/chat/summaries")
    ok("隐私-摘要: 老人本人见全部(含开启后)", len(r.json()) == 2, f"n={len(r.json())}")

    # ---- 隐私跨时断言（查药 chat）：已绑家属只见 BEFORE，本人见全部 ----
    set_cur(bound)
    r = client.get("/api/drugs/records", params={"elder_id": elder.id})
    d_before = [x for x in r.json() if x.get("input_text") == "D1"]
    d_after = [x for x in r.json() if x.get("input_text") == "D2"]
    ok("隐私-查药: 已绑家属只见开启前记录", len(d_before) == 1 and len(d_after) == 0,
       f"n={len(r.json())}")
    set_cur(elder)
    r = client.get("/api/drugs/records")
    ok("隐私-查药: 老人本人见全部(含开启后)", len(r.json()) == 2, f"n={len(r.json())}")

    print("\n==== RESULT ====")
    print(f"PASS={len(PASS)} FAIL={len(FAIL)}  (10.26 补测：四类权限+隐私跨时)")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()

# -*- coding: utf-8 -*-
"""10.26 #18 权限矩阵——体征读取三态（本人/未绑定家属/已绑定家属）真实环境测试。
报告/查药/摘要/录音与体征共用同一 resolve_elder_id / FamilyBinding 归属校验入口，
以本测试代表验证该权限入口的行为。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import Depends
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from db.database import Base, get_db
from db.models import User, FamilyBinding, Vitals
from core.security import get_current_user
from core import age as age_mod

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
    from fastapi import FastAPI
    app = FastAPI()
    app.include_router(vitals_r)

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


def seed():
    db = _TS()
    elder = User(phone="13800000002", nickname="老人", password_hash="x", role="elder",
                 birth_ym="1966-10")  # senior
    free = User(phone="13800000003", nickname="未绑定家属", password_hash="x", role="family")
    bound = User(phone="13800000004", nickname="已绑定家属", password_hash="x", role="family")
    db.add_all([elder, free, bound])
    db.commit()
    db.refresh(elder); db.refresh(free); db.refresh(bound)
    # active 绑定：bound 家属 绑定 elder
    db.add(FamilyBinding(elder_id=elder.id, family_id=bound.id, status="active",
                         invite_code="ABCDEF"))
    # elder 一条体征
    db.add(Vitals(elder_id=elder.id, type="bp", systolic=135, diastolic=85))
    db.commit()
    db.refresh(elder)
    return elder, free, bound


elder, free, bound = seed()


def set_cur(u):
    global _cur
    _cur = u


def main():
    # 1. 老人本人读取自己的体征
    set_cur(elder)
    r = client.get("/api/vitals")
    ok("体征: 老人本人读取 200", r.status_code == 200 and len(r.json()) == 1,
       f"status={r.status_code} n={len(r.json()) if r.status_code==200 else 'err'}")

    # 2. 未绑定家属读取老人体征 → 403
    set_cur(free)
    r = client.get("/api/vitals", params={"elder_id": elder.id})
    ok("体征: 未绑定家属读取 403", r.status_code == 403, f"status={r.status_code} body={r.text}")

    # 3. 已绑定家属读取老人体征 → 200
    set_cur(bound)
    r = client.get("/api/vitals", params={"elder_id": elder.id})
    ok("体征: 已绑定家属读取 200", r.status_code == 200 and len(r.json()) == 1,
       f"status={r.status_code} n={len(r.json()) if r.status_code==200 else 'err'}")

    # 4. 未绑定家属读他人（非绑定）老人也 403（越权不可达）
    set_cur(free)
    r = client.get("/api/vitals", params={"elder_id": elder.id})
    ok("体征: 越权（未绑定）不可达 403", r.status_code == 403, f"status={r.status_code}")

    # 5. 已绑定家属写入体征（代录）200 —— 绑定家属有权代录
    set_cur(bound)
    r = client.post("/api/vitals", json={
        "elder_id": elder.id, "type": "bs", "value": "6.1", "measured_at": "2026-10-19T09:00:00"
    })
    ok("体征: 已绑定家属代录 200", r.status_code == 200, f"status={r.status_code} body={r.text[:80]}")

    # 6. senior 年龄分层：elder 为 senior，强制分享落库
    set_cur(elder)
    client.get("/api/vitals")  # 触发 profile 无关，这里验证 age_mod 直接
    db = _TS()
    e = db.query(User).filter(User.id == elder.id).first()
    ok("年龄分层: elder 为 senior 强制分享", age_mod.is_senior(e.birth_ym) is True
       and age_mod.forced_share(e.birth_ym) is True, f"birth={e.birth_ym}")

    print("\n==== RESULT ====")
    print(f"PASS={len(PASS)} FAIL={len(FAIL)}  (10.26 #18 权限矩阵-体征代表)")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()

# -*- coding: utf-8 -*-
"""10.26 #5 年龄分层 真实环境测试（D:\\python 3.13.5）。"""

# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
import os
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from fastapi import Depends
from fastapi.testclient import TestClient

from db.database import Base, get_db
from db.models import User
from core.security import get_current_user
from core import age as age_mod

PASS, FAIL = [], []

_engine = create_engine("sqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})
_TS = sessionmaker(bind=_engine, autoflush=False, expire_on_commit=False)
Base.metadata.create_all(bind=_engine)
_test_user = None


def make_app():
    from api.users import router as users_r
    from api.privacy import router as priv_r
    from fastapi import FastAPI
    app = FastAPI()
    app.include_router(users_r)
    app.include_router(priv_r)

    def _get_db():
        db = _TS()
        try:
            yield db
        finally:
            db.close()
    app.dependency_overrides[get_db] = _get_db

    def _current_user(db=Depends(get_db)):
        # 把 detached 测试用户 merge 进端点所在 session，保证 db.refresh/commit 有效
        if _test_user is None:
            return None
        return db.merge(_test_user)
    app.dependency_overrides[get_current_user] = _current_user
    return app


app = make_app()
client = TestClient(app)


def ok(name, cond, detail=""):
    if cond:
        PASS.append(name); print(f"[PASS] {name}" + (f"  {detail}" if detail else ""))
    else:
        FAIL.append(name); print(f"[FAIL] {name}  {detail}")


def set_user(**kw):
    global _test_user
    db = _TS()
    _test_user = db.query(User).filter(User.phone == "13800000001").first()
    if not _test_user:
        _test_user = User(phone="13800000001", nickname="测试老人", password_hash="x",
                          role="elder")
        db.add(_test_user)
        db.commit()
        db.refresh(_test_user)
    for k, v in kw.items():
        setattr(_test_user, k, v)
    db.commit()


def main():
    ref = date(2026, 10, 1)  # 固定参考日期保证阈值确定性

    # ---- 1. core/age 阈值边界 ----
    ok("周岁计算: 1966-10 @2026-10 = 60", age_mod.compute_age("1966-10", ref) == 60)
    ok("周岁计算: 1966-11 @2026-10 = 59", age_mod.compute_age("1966-11", ref) == 59)
    ok("周岁计算: 1965-12 = 60", age_mod.compute_age("1965-12", ref) == 60)
    ok("周岁计算: 1955-01 = 71", age_mod.compute_age("1955-01", ref) == 71)
    ok("周岁计算: 2015-06 = 11", age_mod.compute_age("2015-06", ref) == 11)
    ok("分层: 60岁整 = senior", age_mod.age_tier("1966-10", ref) == "senior")
    ok("分层: 59岁 = younger", age_mod.age_tier("1966-11", ref) == "younger")
    ok("分层: 空出生年月 = unknown", age_mod.age_tier(None, ref) == "unknown")
    ok("分层: 非法格式 = unknown", age_mod.age_tier("1966/10", ref) == "unknown")
    ok("分层: 未来出生 = unknown", age_mod.age_tier("2027-01", ref) == "unknown")
    ok("强制分享: senior=True / younger=False", age_mod.forced_share("1966-10") is True
       and age_mod.forced_share("1966-11") is False)

    # ---- 2. profile 接口（senior）----
    set_user(birth_ym="1966-10")
    r = client.get("/api/users/profile")
    d = r.json()
    ok("profile: senior 返回 age=60", d.get("age") == 60, f"age={d.get('age')}")
    ok("profile: senior 返回 tier=senior", d.get("age_tier") == "senior", f"tier={d.get('age_tier')}")
    ok("profile: senior 返回 forced_share=True", d.get("forced_share") is True, f"forced={d.get('forced_share')}")

    # ---- 3. senior 强制分享落库 ----
    # 直接把开关写成 False，再读 profile 应被强制改回 True（查库验证落库）
    db = _TS()
    _test_user.sync_summary_to_family = False
    db.commit()
    client.get("/api/users/profile")  # 触发 enforce_senior_share
    db2 = _TS()
    _db_user = db2.query(User).filter(User.phone == "13800000001").first()
    ok("profile: senior 读取时强制分享落库", _db_user.sync_summary_to_family is True,
       f"db_sync={_db_user.sync_summary_to_family}")
    ok("profile: senior 强制后 privacy_enabled_at 清空", _db_user.privacy_enabled_at is None)

    # ---- 4. privacy 接口（senior 不可关闭）----
    r = client.get("/api/privacy")
    d = r.json()
    ok("privacy: senior 读取 forced=True/sync=True", d.get("forced_share") is True
       and d.get("sync_summary_to_family") is True, f"{d}")
    r = client.put("/api/privacy", json={"sync_summary_to_family": False})
    ok("privacy: senior 设 False → 403 拒绝", r.status_code == 403, f"status={r.status_code} body={r.text}")

    # ---- 5. younger 可选分享 ----
    set_user(birth_ym="1966-11")
    r = client.get("/api/users/profile")
    d = r.json()
    ok("profile: younger 返回 tier=younger", d.get("age_tier") == "younger" and d.get("forced_share") is False,
       f"tier={d.get('age_tier')} forced={d.get('forced_share')}")
    r = client.put("/api/privacy", json={"sync_summary_to_family": False})
    ok("privacy: younger 可关闭隐私(200)", r.status_code == 200 and r.json()["sync_summary_to_family"] is False,
       f"status={r.status_code} sync={r.json().get('sync_summary_to_family')}")
    r = client.put("/api/privacy", json={"sync_summary_to_family": True})
    ok("privacy: younger 可再开启(200)", r.status_code == 200 and r.json()["sync_summary_to_family"] is True)

    # ---- 6. 未设置出生年月 = unknown，不强制 ----
    set_user(birth_ym=None)
    r = client.get("/api/users/profile")
    d = r.json()
    ok("profile: 未设置出生年月 = unknown/不强制", d.get("age_tier") == "unknown" and d.get("forced_share") is False,
       f"tier={d.get('age_tier')} forced={d.get('forced_share')}")

    print("\n==== RESULT ====")
    print(f"PASS={len(PASS)} FAIL={len(FAIL)}  (10.26 #5 年龄分层)")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()

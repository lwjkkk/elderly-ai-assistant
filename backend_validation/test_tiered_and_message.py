# -*- coding: utf-8 -*-
"""10.28 A：#9 事件接 FamilyMessage 持久消息链路 + #12 老人简版/家属详版三段式。真实环境测试。"""
import os
import sys
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import Depends
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from db.database import Base, get_db
from db.models import User, FamilyBinding, FamilyMessage
from core.security import get_current_user, get_optional_user
from core import tiered_answer

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
    from api.messages import router as msgs_r
    from api.routes import router as routes_r
    from fastapi import FastAPI
    app = FastAPI()
    for r in (vitals_r, msgs_r, routes_r):
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
    app.dependency_overrides[get_optional_user] = _current_user
    return app


app = make_app()
client = TestClient(app)


def seed():
    db = _TS()
    elder = User(phone="13800000108", nickname="老人", password_hash="x", role="elder")
    free = User(phone="13800000109", nickname="未绑家属", password_hash="x", role="family")
    bound = User(phone="13800000110", nickname="已绑家属", password_hash="x", role="family")
    db.add_all([elder, free, bound]); db.commit()
    db.refresh(elder); db.refresh(free); db.refresh(bound)
    b = FamilyBinding(elder_id=elder.id, family_id=bound.id, status="active", invite_code="XYZ128")
    db.add(b); db.commit(); db.refresh(b)
    return elder, free, bound, b


elder, free, bound, binding = seed()


def set_cur(u):
    global _cur
    _cur = u


def main():
    # ---- 1. #9 事件写入 FamilyMessage 持久消息链路 ----
    set_cur(elder)
    r = client.post("/api/vitals", json={"type": "bp", "systolic": 152, "diastolic": 96,
                                         "measured_at": "2026-10-28T09:00:00"})
    ok("#9: POST 血压异常 → 200", r.status_code == 200, f"status={r.status_code}")
    set_cur(bound)
    r = client.get(f"/api/messages/{binding.id}")
    health = [m for m in r.json() if m.get("kind") == "health"]
    ok("#9: 家属端消息链路可见异常提醒", r.status_code == 200 and health
       and health[-1]["content"].get("type") == "vital_alert"
       and health[-1]["content"].get("level") == "high",
       f"health_msgs={len(health)} last_level={health[-1]['content'].get('level') if health else '-'}")
    set_cur(free)
    r = client.get(f"/api/messages/{binding.id}")
    ok("#9: 未绑定家属读该会话 → 403", r.status_code == 403, f"status={r.status_code}")

    # ---- 2. #12 三段式核心（真实 LLM）----
    q = "老人血压有点高，平时该注意什么？"
    ref = "血压偏高时，建议规律监测、低盐饮食、保持运动，若持续偏高需就医，切勿自行调药。"
    elder_view = tiered_answer.build(q, ref, "elder")
    ok("#12: 老人简版 source=llm", elder_view["source"] == "llm", f"source={elder_view['source']}")
    ev = elder_view["view"]
    ok("#12: 简版三段齐全", bool(ev["conclusion"]) and bool(ev["advice"]) and bool(ev["seek"]),
       f"c={len(ev['conclusion'])} a={len(ev['advice'])} s={len(ev['seek'])}")
    ok("#12: 简版限长+就医兜底", len(ev["conclusion"]) <= 40 and len(ev["advice"]) <= 48
       and "医生意见为准" in ev["seek"],
       f"c={len(ev['conclusion'])} a={len(ev['advice'])}")
    family_view = tiered_answer.build(q, ref, "family")
    ok("#12: 家属详版三段完整", family_view["source"] == "llm" and bool(family_view["view"]["conclusion"])
       and bool(family_view["view"]["advice"]) and bool(family_view["view"]["seek"]),
       f"source={family_view['source']}")
    ok("#12: 详版含关注点", "关注点" in family_view["view"]["note"])

    # ---- 3. parse_three 容错 ----
    p = tiered_answer.parse_three("【结论】血压偏高。\n【建议】低盐饮食。")
    ok("#12: 缺就医提醒补兜底", p["seek"] == tiered_answer._FALLBACK_SEEK)
    p2 = tiered_answer.parse_three("")
    ok("#12: 空输入不崩溃且有兜底", p2["conclusion"] and p2["advice"] and p2["seek"])

    # ---- 4. LLM 失败确定性降级 ----
    with mock.patch("core.tiered_answer.call_qwen", side_effect=RuntimeError("down")):
        d = tiered_answer.build(q, ref, "elder")
        ok("#12: LLM失败降级 source=deterministic", d["source"] == "deterministic", f"source={d['source']}")
        ok("#12: 降级三段非空", bool(d["view"]["conclusion"]) and bool(d["view"]["advice"]) and bool(d["view"]["seek"]))

    # ---- 5. 接口 /api/chat/tiered（真实 agent+LLM）----
    set_cur(elder)
    r = client.post("/api/chat/tiered", json={"question": "高血压老人平时饮食要注意什么？"})
    j = r.json()
    ok("#12接口: 老人 → role=elder 简版", r.status_code == 200 and j.get("role") == "elder"
       and j["view"]["note"] and len(j["view"]["conclusion"]) <= 40, f"status={r.status_code} source={j.get('source')}")
    set_cur(bound)
    r = client.post("/api/chat/tiered", json={"question": "高血压老人平时饮食要注意什么？"})
    j = r.json()
    ok("#12接口: 家属 → role=family 详版", r.status_code == 200 and j.get("role") == "family"
       and "关注点" in j["view"]["note"], f"status={r.status_code} role={j.get('role')} note={j['view'].get('note')}")

    # ---- 6. 推送通道可插拔适配器 ----
    from services import push as push_svc
    push_svc.clear_sent()
    n = push_svc.send_push(bound.id, "测试提醒", "内容")
    ok("#9push: 默认内存适配器真实可发送", n["receiver_id"] == bound.id and len(push_svc.get_sent()) == 1)
    real = push_svc.RealPushAdapter()
    raised = False
    try:
        real.send(1, "t", "c")
    except ValueError:
        raised = True
    ok("#9push: 真实适配器缺凭证明确拒绝(不假装已发送)", raised)
    mem = push_svc.MemoryPushAdapter(); mem.clear()
    push_svc.set_adapter(mem)
    push_svc.send_push(1, "t", "c")
    ok("#9push: set_adapter 切换可插拔", len(mem.get_sent()) == 1 and len(push_svc.get_sent()) == 1)
    push_svc.set_adapter(push_svc.MemoryPushAdapter())

    print("\n==== RESULT ====")
    print(f"PASS={len(PASS)} FAIL={len(FAIL)}  (10.28 #9持久消息链路 + #12三段式双角色)")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()

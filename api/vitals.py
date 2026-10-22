# 体征接口：录入血压/血糖/心率/体重，按天聚合趋势查询，导出 PDF

import re
import hashlib
import json
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
from collections import defaultdict
from types import SimpleNamespace

from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy import update
from sqlalchemy.exc import IntegrityError

from db.database import get_db
from db.models import (User, FamilyBinding, Vitals, VitalDraftConversation,
                       VitalAlert, FamilyMessage, IdempotencyRecord,
                       NotificationOutbox)
from db.schemas import (
    VitalsCreate, VitalsOut, TrendPoint,
    VitalsSpokenParseRequest, VitalsSpokenDraftOut,
    VitalsSpokenTurnRequest, VitalsSpokenTurnOut, VitalAlertOut,
    VitalsSpokenEditRequest, VitalDraftConfirmOut,
)
from core.security import get_current_user
from core.disclaimer import HEALTH_DISCLAIMER
from core.ocr import recognize_image, OcrUnavailableError
from core.qwen_llm import call_qwen
from core.vitals_draft import parse_spoken_vitals
from core.vitals_conversation import merge_turn, compute_missing, draft_payload, _revalidate
from core import vital_thresholds as vth
from core import age as age_mod
from services import push as push_svc
from services.pdf_export import generate_vitals_pdf

router = APIRouter(prefix="/api/vitals", tags=["体征"])

VALID_TYPES = {"bp", "bs", "hr", "weight"}
BS_MEASUREMENT_CONTEXTS = {"fasting", "postprandial", "random", "unknown"}
_SUBJECT_LABELS = ("妈妈", "母亲", "爸爸", "父亲", "奶奶", "爷爷", "外婆", "外公", "本人", "自己", "我")


def _spoken_subject(db: Session, current: User, elder_id: int, text: str) -> tuple[str | None, bool]:
    """Resolve only explicit account names; family-role words require confirmation."""
    text = text or ""
    target = db.query(User).filter(User.id == elder_id).first()
    if target and target.nickname and target.nickname in text:
        return target.nickname, True
    for label in _SUBJECT_LABELS:
        if label not in text:
            continue
        if label in ("本人", "自己", "我"):
            return label, current.id == elder_id
        # The app does not store trusted kinship labels, so do not guess which
        # bound account “妈妈/爸爸” refers to.
        return label, False
    return (target.nickname if target else None), True


def _parse_measured_at(value: str | None, tz_name: str = "Asia/Shanghai"):
    """解析 ISO 日期时间并统一持久化为 UTC naive datetime。
    无偏移输入默认按 Asia/Shanghai；空值由调用方决定是否采用当前时间。"""
    if not value:
        return None
    raw = value.strip().replace("Z", "+00:00")
    try:
        parsed = datetime.strptime(raw, "%Y-%m-%d") if len(raw) == 10 else datetime.fromisoformat(raw)
    except ValueError:
        raise HTTPException(status_code=400, detail="测量时间格式无效，请使用 ISO 8601 日期时间")
    if parsed.tzinfo is None:
        try:
            parsed = parsed.replace(tzinfo=ZoneInfo(tz_name))
        except Exception:
            raise HTTPException(status_code=400, detail="未知时区，请提供有效 IANA 时区")
    utc_value = parsed.astimezone(timezone.utc).replace(tzinfo=None)
    if utc_value > datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=5):
        raise HTTPException(status_code=400, detail="测量时间不能明显晚于当前时间")
    return utc_value


def resolve_elder_id(db: Session, current: User, elder_id: int | None) -> int:
    """解析目标数据归属：
    - 老人：总是操作自己的数据；
    - 家属：传 elder_id 则必须已绑定该老人；不传则操作自己的本人记录。
    10.26 起：家属读长辈体征/异常事件前，统一走 age.family_access_guard。
    """
    if current.role == "elder":
        if elder_id is not None and elder_id != current.id:
            raise HTTPException(status_code=403, detail="老人账号只能访问本人数据")
        return current.id
    if elder_id is None or elder_id == current.id:
        return current.id
    binding = (
        db.query(FamilyBinding)
        .filter(FamilyBinding.elder_id == elder_id)
        .filter(FamilyBinding.family_id == current.id)
        .filter(FamilyBinding.status == "active")
        .first()
    )
    if not binding:
        raise HTTPException(status_code=403, detail="未绑定该老人，无权操作")
    target_user = db.query(User).filter(User.id == elder_id).first()
    if target_user is None:
        raise HTTPException(status_code=404, detail="老人账号不存在")
    allowed, reason = age_mod.family_access_guard(db, current, target_user)
    if not allowed:
        detail = {
            "birth_missing": "老人资料不完整（缺出生年月），请补全出生年月后再开放家属访问",
            "privacy_off": "老人未开启健康资料分享，家属暂不可见",
        }.get(reason, "无权访问该老人健康资料")
        raise HTTPException(status_code=403, detail=detail)
    return elder_id


def _maybe_create_alert(db: Session, vital: Vitals) -> VitalAlert | None:
    """Stage an alert, family message and persistent notification outbox in the caller's transaction."""
    ev = vth.evaluate(vital.type, vital.systolic, vital.diastolic, vital.value,
                      measurement_context=vital.measurement_context)
    if not ev or not ev["abnormal"]:
        return None
    alert = VitalAlert(
        elder_id=vital.elder_id, vital_id=vital.id, threshold_version="v1",
        measured_at=vital.measured_at, vital_type=vital.type,
        systolic=vital.systolic, diastolic=vital.diastolic, value=vital.value,
        measurement_context=vital.measurement_context,
        level=ev["level"], message=ev["message"], source=ev["source"],
    )
    db.add(alert)
    db.flush()

    elder = db.query(User).filter(User.id == vital.elder_id).first()
    tier = age_mod.age_tier(elder.birth_ym if elder else None)
    allow_push = tier == age_mod.TIER_SENIOR or (
        tier == age_mod.TIER_YOUNGER and elder is not None
        and elder.sync_summary_to_family is not False
    )
    if tier == age_mod.TIER_SENIOR and elder is not None:
        elder.sync_summary_to_family = True
        elder.privacy_enabled_at = None
    if not allow_push:
        return alert

    bindings = (db.query(FamilyBinding)
                .filter(FamilyBinding.elder_id == vital.elder_id,
                        FamilyBinding.status == "active",
                        FamilyBinding.family_id.isnot(None)).all())
    content = f"老人体征异常提示（{ev['level']}）：{ev['message']}"
    channel = "in_app" if push_svc.adapter_name() == "memory" else "push"
    for binding in bindings:
        db.add(FamilyMessage(
            binding_id=binding.id, sender_id=vital.elder_id, kind="health",
            content={"type": "vital_alert", "origin": "system",
                     "elder_id": vital.elder_id, "vital_id": vital.id,
                     "alert_id": alert.id, "vital_type": vital.type,
                     "level": ev["level"], "message": ev["message"],
                     "source": ev["source"]},
        ))
        db.add(NotificationOutbox(
            elder_id=vital.elder_id, receiver_id=binding.family_id,
            alert_id=alert.id, channel=channel, status="pending",
            title="体征异常提醒", content=content,
            dedupe_key=f"vital-alert:{vital.id}:family:{binding.family_id}",
        ))
    db.flush()
    return alert


def _notification_status(db: Session, vital_id: int) -> str:
    alert = db.query(VitalAlert).filter_by(vital_id=vital_id).first()
    if alert is None:
        return "no_alert"
    from services.notification_outbox import status_for_alert
    return status_for_alert(db, alert.id)


@router.post("", response_model=VitalsOut)
def create_vital(payload: VitalsCreate,
                 db: Session = Depends(get_db),
                 current: User = Depends(get_current_user)):
    """录入一条体征记录。"""
    if payload.type not in VALID_TYPES:
        raise HTTPException(status_code=400, detail=f"类型只能是 {VALID_TYPES}")

    context = payload.measurement_context or "unknown"
    if payload.type == "bs" and context not in BS_MEASUREMENT_CONTEXTS:
        raise HTTPException(
            status_code=400,
            detail="血糖测量场景只能是 fasting、postprandial、random 或 unknown",
        )
    if payload.type != "bs" and context not in {"unknown"}:
        raise HTTPException(status_code=400, detail="只有血糖记录可以填写测量场景")

    # 血压必须同时有收缩压和舒张压，并校验合理范围
    if payload.type == "bp":
        if payload.systolic is None or payload.diastolic is None:
            raise HTTPException(status_code=400, detail="血压需同时填写收缩压和舒张压")
        if not (30 <= payload.systolic <= 300):
            raise HTTPException(status_code=400, detail=f"收缩压值 {payload.systolic} 不在合理范围 30~300 mmHg")
        if not (20 <= payload.diastolic <= 250):
            raise HTTPException(status_code=400, detail=f"舒张压值 {payload.diastolic} 不在合理范围 20~250 mmHg")
        if payload.systolic <= payload.diastolic:
            raise HTTPException(status_code=400, detail="收缩压必须大于舒张压")

    # 血糖校验
    if payload.type == "bs":
        if payload.value is None:
            raise HTTPException(status_code=400, detail="血糖记录必须填写数值")
        if not (1.0 <= payload.value <= 50.0):
            raise HTTPException(status_code=400, detail=f"血糖值 {payload.value} 不在合理范围 1.0~50.0 mmol/L")

    # 心率校验
    if payload.type == "hr":
        if payload.value is None:
            raise HTTPException(status_code=400, detail="心率记录必须填写数值")
        if not (30 <= payload.value <= 250):
            raise HTTPException(status_code=400, detail=f"心率值 {payload.value} 不在合理范围 30~250 次/分")

    # 体重校验
    if payload.type == "weight":
        if payload.value is None:
            raise HTTPException(status_code=400, detail="体重记录必须填写数值")
        if not (20.0 <= payload.value <= 300.0):
            raise HTTPException(status_code=400, detail=f"体重值 {payload.value} 不在合理范围 20~300 kg")

    elder_id = resolve_elder_id(db, current, payload.elder_id)

    vital = Vitals(
        elder_id=elder_id,
        type=payload.type,
        systolic=payload.systolic,
        diastolic=payload.diastolic,
        value=payload.value,
        measurement_context=context if payload.type == "bs" else None,
        measured_at=_parse_measured_at(payload.measured_at) or datetime.now(timezone.utc).replace(tzinfo=None),
    )
    db.add(vital)
    db.flush()
    alert = _maybe_create_alert(db, vital)
    db.commit()
    db.refresh(vital)
    if alert is not None:
        from services.notification_outbox import process_pending, status_for_alert
        try:
            process_pending(sessionmaker(bind=db.get_bind()), alert_id=alert.id)
            notification_status = status_for_alert(db, alert.id)
        except Exception:
            notification_status = "pending"
        return VitalsOut.model_validate(vital).model_copy(update={"notification_status": notification_status})
    return vital


@router.get("/alerts", response_model=list[VitalAlertOut])
def list_vital_alerts(elder_id: int | None = None,
                      days: int = 90,
                      limit: int = 100,
                      offset: int = 0,
                      db: Session = Depends(get_db),
                      current: User = Depends(get_current_user)):
    """体征异常事件列表：老人本人看自己；绑定家属传 elder_id 看老人。仅提示，不替代诊断。"""
    target = resolve_elder_id(db, current, elder_id)
    if not 1 <= days <= 3650:
        raise HTTPException(status_code=400, detail="days 必须在 1 到 3650 之间")
    if not 1 <= limit <= 200 or offset < 0:
        raise HTTPException(status_code=400, detail="limit 必须在 1 到 200 之间，offset 不能为负数")
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=days)
    return (
        db.query(VitalAlert)
        .filter(VitalAlert.elder_id == target, VitalAlert.created_at >= cutoff)
        .order_by(VitalAlert.created_at.desc())
        .offset(offset).limit(limit)
        .all()
    )


@router.get("", response_model=list[VitalsOut])
def list_vitals(vital_type: str | None = None,
                elder_id: int | None = None,
                days: int = 30,
                db: Session = Depends(get_db),
                current: User = Depends(get_current_user)):
    """查询体征记录，默认最近 30 天，可按类型筛选。"""
    target = resolve_elder_id(db, current, elder_id)
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=days)

    query = db.query(Vitals).filter(
        Vitals.elder_id == target,
        Vitals.measured_at >= cutoff,
    )
    if vital_type:
        if vital_type not in VALID_TYPES:
            raise HTTPException(status_code=400, detail=f"类型只能是 {VALID_TYPES}")
        query = query.filter(Vitals.type == vital_type)

    return query.order_by(Vitals.measured_at.desc()).all()


@router.get("/trend", response_model=dict[str, list[TrendPoint]])
def trend(vital_type: str | None = None,
          elder_id: int | None = None,
          days: int = 30,
          db: Session = Depends(get_db),
          current: User = Depends(get_current_user)):
    """按天聚合趋势数据，前端直接用来画曲线图。"""
    target = resolve_elder_id(db, current, elder_id)
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=days)

    query = db.query(Vitals).filter(
        Vitals.elder_id == target,
        Vitals.measured_at >= cutoff,
    )
    if vital_type:
        if vital_type not in VALID_TYPES:
            raise HTTPException(status_code=400, detail=f"类型只能是 {VALID_TYPES}")
        query = query.filter(Vitals.type == vital_type)

    records = query.order_by(Vitals.measured_at).all()

    # 按日期分组
    grouped: dict[str, list] = defaultdict(list)
    for r in records:
        day = (r.measured_at.replace(tzinfo=timezone.utc).astimezone(ZoneInfo("Asia/Shanghai"))
               .strftime("%Y-%m-%d")) if r.measured_at else "unknown"
        grouped[day].append(r)

    result: dict[str, list[TrendPoint]] = {}
    for day, items in sorted(grouped.items()):
        # 同一天有多条记录时取平均
        bp_items = [i for i in items if i.type == "bp"]
        other = [i for i in items if i.type != "bp"]

        if bp_items:
            avg_sys = round(sum(i.systolic for i in bp_items if i.systolic) / len(bp_items))
            avg_dia = round(sum(i.diastolic for i in bp_items if i.diastolic) / len(bp_items))
            result.setdefault("bp", []).append(TrendPoint(date=day, systolic=avg_sys, diastolic=avg_dia))

        for item in other:
            result.setdefault(item.type, []).append(
                TrendPoint(date=day, value=item.value))

    return result


@router.get("/export")
def export_pdf(vital_type: str | None = None,
               elder_id: int | None = None,
               days: int = 30,
               db: Session = Depends(get_db),
               current: User = Depends(get_current_user)):
    """导出体征 PDF（含趋势图 + 数据表 + 免责声明）。"""
    target = resolve_elder_id(db, current, elder_id)
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=days)

    query = db.query(Vitals).filter(
        Vitals.elder_id == target,
        Vitals.measured_at >= cutoff,
    )
    if vital_type:
        query = query.filter(Vitals.type == vital_type)
    records = query.order_by(Vitals.measured_at).all()

    # 无数据时直接返回 4xx + 中文提示，避免前端拿到空 PDF
    if not records:
        raise HTTPException(
            status_code=400,
            detail="该老人近期暂无体征记录，无法导出，请先录入体征数据",
        )

    elder = db.query(User).filter(User.id == target).first()
    try:
        pdf_bytes = generate_vitals_pdf(records, elder.nickname if elder else "老人", HEALTH_DISCLAIMER)
    except ModuleNotFoundError as e:
        raise HTTPException(status_code=500, detail=f"PDF 导出缺少依赖：{e}，请联系管理员安装 reportlab/matplotlib")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"PDF 生成失败：{e}")

    if not pdf_bytes[:5] == b"%PDF-":
        raise HTTPException(status_code=500, detail="PDF 生成异常，未返回有效文件")

    return StreamingResponse(
        iter([pdf_bytes]),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=vitals_{target}.pdf"},
    )


# 拍照体征识别入口已按 10.26 团队决定删除（统一改走口述体征草稿）。
# 体检报告 OCR（core.ocr.recognize_image）仍被 reports.py / drugs.py 复用，保留。


@router.post("/parse-spoken", response_model=VitalsSpokenDraftOut)
def parse_spoken_vitals_endpoint(payload: VitalsSpokenParseRequest,
                                 db: Session = Depends(get_db),
                                 current: User = Depends(get_current_user)):
    """语音转写/口述体征草稿解析：从口述文本识别体征意图与字段，只产出草稿，不落库。
    前端展示/编辑/确认后，再调 POST /api/vitals 落库（复用现有范围校验）。"""
    # 沿用老人/家属归属校验（家属需绑定，老人默认自己），与拍照识别一致
    resolve_elder_id(db, current, payload.elder_id)

    draft = parse_spoken_vitals(payload.text, payload.hint_type)
    if draft is None:
        return VitalsSpokenDraftOut(hit=False, disclaimer=HEALTH_DISCLAIMER)
    return VitalsSpokenDraftOut(hit=True, **draft, disclaimer=HEALTH_DISCLAIMER)


def _conv_access_check(db: Session, current: User, conv: VitalDraftConversation):
    """体征会话归属校验：老人只能操作自己的；家属需绑定该老人。"""
    if conv.elder_id == current.id:
        return
    if current.role == "elder":
        if conv.elder_id != current.id:
            raise HTTPException(status_code=403, detail="无权访问该体征会话")
    else:
        resolve_elder_id(db, current, conv.elder_id)


@router.post("/draft-conversations", response_model=VitalsSpokenTurnOut)
def spoken_vital_turn(payload: VitalsSpokenTurnRequest,
                      db: Session = Depends(get_db),
                      current: User = Depends(get_current_user)):
    """体征口述多轮会话：新一轮口述文本 → 合并草稿 + 判定缺字段 + 返回追问。
    不写 vitals 表；只有 confirm 端点才复用现有 POST /api/vitals 落库。"""
    elder_id = resolve_elder_id(db, current, payload.elder_id)

    expected_version = None
    if payload.session_id:
        conv = db.get(VitalDraftConversation, payload.session_id)
        if not conv or conv.elder_id != elder_id:
            raise HTTPException(status_code=404, detail="体征会话不存在或无权访问")
        if conv.status in ("confirmed", "cancelled"):
            raise HTTPException(status_code=400, detail="该体征会话已结束，请重新发起")
        expected_version = conv.version
        # 在脱离 ORM 跟踪的快照上合并，再通过版本条件写回，避免续轮覆盖并发确认/取消。
        db.expunge(conv)
    else:
        conv = VitalDraftConversation(elder_id=elder_id, status="collecting",
                                     version=0, subject_confirmed=True)
        db.add(conv)

    target_for_subject = db.query(User).filter(User.id == elder_id).first()
    explicit_subject = any(label in payload.text for label in _SUBJECT_LABELS)
    explicit_subject = explicit_subject or bool(
        target_for_subject and target_for_subject.nickname
        and target_for_subject.nickname in payload.text
    )
    if explicit_subject:
        subject_label, subject_confirmed = _spoken_subject(db, current, elder_id, payload.text)
        if subject_label:
            conv.subject_label = subject_label
            conv.subject_confirmed = subject_confirmed
    elif not conv.subject_label and target_for_subject:
        conv.subject_label = target_for_subject.nickname
        conv.subject_confirmed = True
    elif conv.subject_confirmed is False and re.fullmatch(
            r"\s*(?:对|是|确认|确定|就记这个人|按这个对象|没错)[。！!，,\s]*", payload.text):
        conv.subject_confirmed = True
    iso_text = re.search(r"\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})?\b", payload.text)
    if iso_text:
        _parse_measured_at(iso_text.group(0))
    merge_turn(conv, payload.text, payload.hint_type)
    # measured_at 归一为 datetime（草稿解析器返回 ISO 字符串）
    if isinstance(conv.measured_at, str) and conv.measured_at:
        conv.measured_at = _parse_measured_at(conv.measured_at)
    if conv.status == "ready" and compute_missing(conv):
        conv.missing = compute_missing(conv)
        conv.last_question = "请补充缺失信息后再确认保存。"
        conv.status = "collecting"
    if expected_version is not None:
        changes = {name: getattr(conv, name) for name in (
            "type", "systolic", "diastolic", "value", "unit", "measurement_context",
            "measured_text", "measured_at", "raw_text", "subject_label", "subject_confirmed",
            "missing", "last_question", "status", "version",
        )}
        changed = db.execute(update(VitalDraftConversation)
            .where(VitalDraftConversation.id == conv.id,
                   VitalDraftConversation.version == expected_version,
                   VitalDraftConversation.status.in_(("collecting", "ready")))
            .values(**changes))
        if changed.rowcount != 1:
            db.rollback()
            raise HTTPException(status_code=409, detail="草稿已被其他请求修改，请重新读取后再补充")
    db.commit()
    if expected_version is not None:
        conv = db.get(VitalDraftConversation, conv.id)
    else:
        db.refresh(conv)

    return VitalsSpokenTurnOut(
        session_id=conv.id,
        status=conv.status,
        missing=list(conv.missing or []),
        question=conv.last_question or "",
        can_confirm=(conv.status == "ready"),
        draft=draft_payload(conv),
        disclaimer=HEALTH_DISCLAIMER,
        elder_id=conv.elder_id,
        subject_label=conv.subject_label,
        subject_confirmed=conv.subject_confirmed,
        version=conv.version,
        confirmed_vital_id=conv.confirmed_vital_id,
    )


@router.get("/draft-conversations/{conv_id}", response_model=VitalsSpokenTurnOut)
def get_vital_draft(conv_id: int,
                    db: Session = Depends(get_db),
                    current: User = Depends(get_current_user)):
    """Read a draft without changing raw input, status or version."""
    conv = db.get(VitalDraftConversation, conv_id)
    if not conv:
        raise HTTPException(status_code=404, detail="体征会话不存在")
    _conv_access_check(db, current, conv)
    return VitalsSpokenTurnOut(
        session_id=conv.id, status=conv.status,
        missing=list(conv.missing or []), question=conv.last_question or "",
        can_confirm=conv.status == "ready", draft=draft_payload(conv),
        elder_id=conv.elder_id, subject_label=conv.subject_label,
        subject_confirmed=conv.subject_confirmed, version=conv.version,
        confirmed_vital_id=conv.confirmed_vital_id,
    )


@router.patch("/draft-conversations/{conv_id}", response_model=VitalsSpokenTurnOut)
def edit_vital_draft(conv_id: int, payload: VitalsSpokenEditRequest,
                     db: Session = Depends(get_db),
                     current: User = Depends(get_current_user)):
    """Apply explicit structured edits with optimistic version checking; never writes vitals."""
    conv = db.get(VitalDraftConversation, conv_id)
    if not conv:
        raise HTTPException(status_code=404, detail="体征会话不存在")
    _conv_access_check(db, current, conv)
    if conv.status in ("confirmed", "cancelled"):
        raise HTTPException(status_code=409, detail="已结束的体征会话不能编辑")
    if conv.version != payload.version:
        raise HTTPException(status_code=409, detail="草稿已被其他请求修改，请重新读取后再编辑")

    fields = payload.model_fields_set
    values = {name: getattr(conv, name) for name in (
        "type", "systolic", "diastolic", "value", "measurement_context",
        "measured_at", "unit", "subject_label", "subject_confirmed", "raw_text",
    )}
    edits = {}
    if "type" in fields:
        new_type = payload.type
        if new_type not in VALID_TYPES:
            raise HTTPException(status_code=400, detail="体征类型无效")
        if new_type != values["type"]:
            values.update({"systolic": None, "diastolic": None, "value": None})
            values["measurement_context"] = "unknown"
        values["type"] = new_type
        values["unit"] = {"bp": "mmHg", "bs": "mmol/L", "hr": "次/分", "weight": "kg"}[new_type]
        edits.update(type=new_type, systolic=values["systolic"],
                     diastolic=values["diastolic"], value=values["value"],
                     measurement_context=values["measurement_context"], unit=values["unit"])
    for name in ("systolic", "diastolic", "value", "measurement_context", "subject_label", "subject_confirmed"):
        if name in fields:
            value = getattr(payload, name)
            if name == "subject_confirmed" and value is None:
                raise HTTPException(status_code=400, detail="记录对象确认状态不能为空")
            values[name] = value
            edits[name] = value
    if "measured_at" in fields:
        if payload.measured_at and len(payload.measured_at.strip()) == 10:
            raise HTTPException(status_code=400, detail="草稿测量时间需包含日期和时刻")
        values["measured_at"] = (_parse_measured_at(payload.measured_at, payload.timezone or "Asia/Shanghai")
                                 if payload.measured_at else None)
        edits["measured_at"] = values["measured_at"]

    if values["type"] == "bs":
        if values["measurement_context"] not in BS_MEASUREMENT_CONTEXTS:
            raise HTTPException(status_code=400, detail="血糖测量场景无效")
    elif values["measurement_context"] not in (None, "unknown"):
        raise HTTPException(status_code=400, detail="只有血糖记录可以填写测量场景")

    candidate = SimpleNamespace(**values)
    missing = compute_missing(candidate)
    errors = _revalidate(candidate) if candidate.type else []
    status = "collecting" if missing or errors else "ready"
    from core.vitals_conversation import build_question
    edits.update(missing=missing, last_question=build_question(candidate, missing, errors),
                 status=status, version=conv.version + 1)
    changed = db.execute(update(VitalDraftConversation)
        .where(VitalDraftConversation.id == conv_id,
               VitalDraftConversation.version == payload.version,
               VitalDraftConversation.status.in_(("collecting", "ready")))
        .values(**edits))
    if changed.rowcount != 1:
        db.rollback()
        raise HTTPException(status_code=409, detail="草稿版本冲突或会话已结束，请重新读取")
    db.commit()
    conv = db.get(VitalDraftConversation, conv_id)
    return VitalsSpokenTurnOut(
        session_id=conv.id, status=conv.status, missing=list(conv.missing or []),
        question=conv.last_question or "", can_confirm=conv.status == "ready",
        draft=draft_payload(conv), elder_id=conv.elder_id,
        subject_label=conv.subject_label, subject_confirmed=conv.subject_confirmed,
        version=conv.version, confirmed_vital_id=conv.confirmed_vital_id,
    )


@router.post("/draft-conversations/{conv_id}/confirm", response_model=VitalDraftConfirmOut)
def confirm_vital_draft(conv_id: int,
                        idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
                        db: Session = Depends(get_db),
                        current: User = Depends(get_current_user)):
    """Atomically commit a draft, its alert/outbox and replay record."""
    conv = db.get(VitalDraftConversation, conv_id)
    if not conv:
        raise HTTPException(status_code=404, detail="体征会话不存在")
    _conv_access_check(db, current, conv)
    key = (idempotency_key or f"vital-draft-confirm:{conv_id}").strip()
    if not key or len(key) > 120:
        raise HTTPException(status_code=400, detail="Idempotency-Key 长度必须为 1 到 120 个字符")
    request_hash = hashlib.sha256(f"confirm:{conv_id}".encode("utf-8")).hexdigest()
    replay = db.query(IdempotencyRecord).filter(
        IdempotencyRecord.user_id == current.id,
        IdempotencyRecord.key == key).first()
    if replay:
        if replay.request_hash != request_hash:
            raise HTTPException(status_code=409, detail="Idempotency-Key 已用于不同请求")
        result = dict(replay.response_json)
        result["notification_status"] = _notification_status(db, result["confirmed_vital_id"])
        return result
    if conv.status == "confirmed":
        vital = db.get(Vitals, conv.confirmed_vital_id) if conv.confirmed_vital_id else None
        if vital is None:
            vital = db.query(Vitals).filter(Vitals.draft_session_id == conv_id).first()
        if vital is None:
            raise HTTPException(status_code=409, detail="会话状态异常，未找到已确认体征记录")
        result = VitalsOut.model_validate(vital).model_dump(mode="json")
        result.update(session_id=conv.id, status="confirmed", confirmed_vital_id=vital.id,
                      notification_status=_notification_status(db, vital.id))
        db.add(IdempotencyRecord(user_id=current.id, key=key,
                                 request_hash=request_hash, response_json=result))
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            replay = db.query(IdempotencyRecord).filter_by(user_id=current.id, key=key).first()
            if not replay or replay.request_hash != request_hash:
                raise HTTPException(status_code=409, detail="Idempotency-Key 已用于不同请求")
            return replay.response_json
        return result
    if conv.status == "cancelled":
        raise HTTPException(status_code=409, detail="该体征会话已取消，无法确认")
    if conv.status != "ready":
        raise HTTPException(status_code=400, detail="信息尚未齐全，无法确认")

    missing = compute_missing(conv)
    if missing:
        raise HTTPException(status_code=400, detail=f"仍有缺失字段：{missing}，请先补齐")
    errors = _revalidate(conv)
    if errors:
        raise HTTPException(status_code=400, detail=errors[0])
    if not conv.subject_confirmed:
        raise HTTPException(status_code=400, detail="请先确认体征记录对象")
    if conv.measured_at is None:
        raise HTTPException(status_code=400, detail="请明确测量时间，或编辑草稿选择按现在记录")

    vital = Vitals(
        elder_id=conv.elder_id, type=conv.type, systolic=conv.systolic,
        diastolic=conv.diastolic, value=conv.value,
        measurement_context=conv.measurement_context if conv.type == "bs" else None,
        measured_at=conv.measured_at, draft_session_id=conv.id,
    )
    db.add(vital)
    try:
        db.flush()
        alert = _maybe_create_alert(db, vital)
        changed = db.execute(update(VitalDraftConversation)
            .where(VitalDraftConversation.id == conv.id,
                   VitalDraftConversation.version == conv.version,
                   VitalDraftConversation.status == "ready")
            .values(status="confirmed", confirmed_vital_id=vital.id,
                    version=conv.version + 1))
        if changed.rowcount != 1:
            db.rollback()
            existing = db.query(Vitals).filter(Vitals.draft_session_id == conv_id).first()
            if existing:
                result = VitalsOut.model_validate(existing).model_dump(mode="json")
                result.update(session_id=conv_id, status="confirmed",
                              confirmed_vital_id=existing.id,
                              notification_status=_notification_status(db, existing.id))
                return result
            raise HTTPException(status_code=409, detail="草稿已被确认或修改，请重新读取")
        notification_status = "pending" if alert is not None else "no_alert"
        result = VitalsOut.model_validate(vital).model_dump(mode="json")
        result.update(session_id=conv.id, status="confirmed",
                      confirmed_vital_id=vital.id,
                      notification_status=notification_status)
        db.add(IdempotencyRecord(user_id=current.id, key=key,
                                 request_hash=request_hash, response_json=result))
        db.commit()
    except IntegrityError:
        db.rollback()
        existing = db.query(Vitals).filter(Vitals.draft_session_id == conv_id).first()
        if not existing:
            raise HTTPException(status_code=409, detail="确认发生并发冲突，请重新读取草稿")
        result = VitalsOut.model_validate(existing).model_dump(mode="json")
        result.update(session_id=conv_id, status="confirmed",
                      confirmed_vital_id=existing.id,
                      notification_status=_notification_status(db, existing.id))
        return result

    if alert is not None:
        from services.notification_outbox import process_pending, status_for_alert
        try:
            process_pending(sessionmaker(bind=db.get_bind()), alert_id=alert.id)
            result["notification_status"] = status_for_alert(db, alert.id)
            replay = db.query(IdempotencyRecord).filter_by(user_id=current.id, key=key).first()
            if replay:
                replay.response_json = result
                db.commit()
        except Exception:
            result["notification_status"] = "pending"
    return result


@router.delete("/draft-conversations/{conv_id}")
def cancel_vital_draft(conv_id: int,
                       db: Session = Depends(get_db),
                       current: User = Depends(get_current_user)):
    """取消体征会话：标记 cancelled，不写 vitals 表。"""
    conv = db.get(VitalDraftConversation, conv_id)
    if not conv:
        raise HTTPException(status_code=404, detail="体征会话不存在")
    _conv_access_check(db, current, conv)
    if conv.status == "confirmed":
        raise HTTPException(status_code=409, detail="该会话已确认入库，不能取消")
    if conv.status == "cancelled":
        return {"ok": True, "status": "cancelled", "session_id": conv.id}
    changed = db.execute(update(VitalDraftConversation)
        .where(VitalDraftConversation.id == conv_id,
               VitalDraftConversation.version == conv.version,
               VitalDraftConversation.status.in_(("collecting", "ready")))
        .values(status="cancelled", version=conv.version + 1))
    if changed.rowcount != 1:
        db.rollback()
        latest = db.get(VitalDraftConversation, conv_id)
        if latest and latest.status == "cancelled":
            return {"ok": True, "status": "cancelled", "session_id": conv_id}
        raise HTTPException(status_code=409, detail="会话状态已变化，请重新读取")
    db.commit()
    return {"ok": True, "status": "cancelled", "session_id": conv_id}


# 各体征类型对应的固定单位
_UNIT_BY_TYPE = {"bp": "mmHg", "bs": "mmol/L", "hr": "次/分", "weight": "kg"}


def _parse_vitals_llm(text: str, hint_type: str | None) -> dict | None:
    """从 LLM 输出里提取体征字段，按类型固定单位并换算。
    bp 必须有收缩压+舒张压；bs/hr/weight 必须有 value。"""
    def _gint(p):
        m = re.search(rf"{p}[:：]\s*([+-]?\d+)", text)
        return int(m.group(1)) if m else None

    def _gfloat(p):
        m = re.search(rf"{p}[:：]\s*([+-]?\d+(?:\.\d+)?)", text)
        return float(m.group(1)) if m else None

    def _gunit(p="UNIT"):
        m = re.search(rf"{p}[:：]\s*(\S+)", text)
        return m.group(1).strip() if m else ""

    t = (hint_type or "").lower() or "bp"
    m_type = re.search(r"TYPE[:：]\s*(\w+)", text)
    if m_type:
        cand = m_type.group(1).strip().lower()
        if cand in VALID_TYPES:
            t = cand

    result = {"type": t, "systolic": None, "diastolic": None, "value": None,
              "unit": _UNIT_BY_TYPE.get(t), "confidence": 0.85}
    conf = _gfloat("CONFIDENCE")
    if conf is not None:
        result["confidence"] = round(min(max(conf, 0.0), 1.0), 2)

    if t == "bp":
        sys, dia = _gint("SYSTOLIC"), _gint("DIASTOLIC")
        if sys is None or dia is None:
            return None
        # 基本合理性校验，防止 OCR/LLM 把序号或无关数字当成血压
        if not (30 <= sys <= 300 and 20 <= dia <= 250 and sys > dia):
            return None
        result["systolic"], result["diastolic"] = sys, dia
    else:
        val = _gfloat("VALUE")
        if val is None:
            return None
        if t == "bs":
            # 血糖统一换算成 mmol/L（mg/dL ÷ 18）
            unit = _gunit().lower().replace(" ", "")
            if unit in ("mg/dl", "mgdl"):
                val = val / 18.0
            # 合理范围 1~50 mmol/L
            if not (1.0 <= val <= 50.0):
                return None
            result["value"] = round(val, 2)
        elif t == "weight":
            # 体重保留一位小数，合理范围 20~300 kg
            if not (20.0 <= val <= 300.0):
                return None
            result["value"] = round(val, 1)
        else:  # hr 心率 30~250 次/分
            if not (30.0 <= val <= 250.0):
                return None
            result["value"] = float(int(round(val)))
    return result


def _fallback_parse_ocr(ocr_text: str, hint_type: str | None) -> dict | None:
    """LLM 解析失败时的保守兜底：优先依赖指标标签/单位，不猜测日期等无关数字。"""
    text = ocr_text.upper()
    t = (hint_type or "").lower() or "bp"

    def _number(value: str) -> float:
        return float(value.replace(",", "."))

    number_pattern = r"([+-]?\d+(?:[.,]\d+)?)"

    if t == "bp":
        # 先找明确标签，兼容设备英文缩写和中文“高压/低压、收缩压/舒张压”。
        m_sys = re.search(rf"(?:SYS(?:TOLIC)?|收缩压|高压)\s*[:：]?\s*(\d{{2,3}})", text)
        m_dia = re.search(rf"(?:DIA(?:STOLIC)?|舒张压|低压)\s*[:：]?\s*(\d{{2,3}})", text)
        if m_sys and m_dia:
            sys, dia = int(m_sys.group(1)), int(m_dia.group(1))
            if 30 <= sys <= 300 and 20 <= dia <= 250 and sys > dia:
                return {"type": "bp", "systolic": sys, "diastolic": dia,
                        "value": None, "unit": "mmHg", "confidence": 0.7}

        # 无标签时只接受同一行里明显成对的血压格式，跳过日期等其他数字。
        for line in ocr_text.splitlines():
            pairs = re.findall(r"(?<!\d)(\d{2,3})\s*/\s*(\d{2,3})(?!\d)", line)
            if not pairs:
                pairs = re.findall(r"(?<!\d)(\d{2,3})\s+(\d{2,3})(?!\d)", line)
            for systolic, diastolic in pairs:
                sys, dia = int(systolic), int(diastolic)
                if 30 <= sys <= 300 and 20 <= dia <= 250 and sys > dia:
                    return {"type": "bp", "systolic": sys, "diastolic": dia,
                            "value": None, "unit": "mmHg", "confidence": 0.6}
        return None

    specs = {
        "bs": {
            "labels": ("血糖", "GLUCOSE", "GLU", r"\bBS\b"),
            "units": ("MMOL/L", "MG/DL", "MGDL"),
            "minimum": 1.0, "maximum": 50.0, "unit": "mmol/L",
        },
        "hr": {
            "labels": ("心率", "脉搏", "PULSE", "PUL", "BPM", r"\bHR\b"),
            "units": ("BPM", "次/分", "次/min"),
            "minimum": 30.0, "maximum": 250.0, "unit": "次/分",
        },
        "weight": {
            "labels": ("体重", "WEIGHT", r"\bWT\b"),
            "units": ("KG", "公斤", "千克"),
            "minimum": 20.0, "maximum": 300.0, "unit": "kg",
        },
    }
    spec = specs.get(t)
    if not spec:
        return None

    for line in ocr_text.splitlines():
        upper_line = line.upper()
        label_match = next(
            (re.search(label, upper_line) for label in spec["labels"] if re.search(label, upper_line)),
            None,
        )
        unit_match = next(
            (re.search(unit, upper_line) for unit in spec["units"] if re.search(unit, upper_line)),
            None,
        )

        # 用标签定位数值，日期/序号位于标签之前时不会被选中。
        if label_match:
            value_text = line[label_match.end():]
            if unit_match and unit_match.start() >= label_match.end():
                candidates = re.findall(number_pattern, line[label_match.end():unit_match.start()])
                candidates = candidates[-1:]
            else:
                candidates = re.findall(number_pattern, value_text)[:1]
            if not candidates:
                continue
            value = _number(candidates[0])
        elif unit_match:
            # 无标签时，单位紧邻指标值也可确定数值；不扫描整张图中的任意数字。
            before_unit = line[:unit_match.start()]
            candidates = re.findall(number_pattern, before_unit)
            if not candidates:
                after_unit = re.findall(number_pattern, line[unit_match.end():])
                if not after_unit:
                    continue
                value = _number(after_unit[0])
            else:
                value = _number(candidates[-1])
        else:
            # 只接受单独显示的数值，避免把日期中的月份/日期当体征。
            if not re.fullmatch(rf"\s*{number_pattern}\s*", line):
                continue
            value = _number(re.fullmatch(rf"\s*{number_pattern}\s*", line).group(1))

        if t == "bs" and unit_match and unit_match.group(0).upper() in ("MG/DL", "MGDL"):
            value /= 18.0
        if spec["minimum"] <= value <= spec["maximum"]:
            if t == "bs":
                value = round(value, 2)
            elif t == "weight":
                value = round(value, 1)
            else:
                value = float(int(round(value)))
            return {"type": t, "systolic": None, "diastolic": None,
                    "value": value, "unit": spec["unit"], "confidence": 0.6}

    return None


@router.delete("/{vital_id}")
def delete_vital(vital_id: int,
                 db: Session = Depends(get_db),
                 current: User = Depends(get_current_user)):
    """删除本人录入的体征记录。"""
    record = db.query(Vitals).filter(Vitals.id == vital_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="体征记录不存在")
    if record.elder_id != current.id:
        raise HTTPException(status_code=403, detail="只能删除本人录入的体征记录")
    db.delete(record)
    db.commit()
    return {"ok": True}

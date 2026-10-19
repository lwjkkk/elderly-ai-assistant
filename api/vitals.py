# 体征接口：录入血压/血糖/心率/体重，按天聚合趋势查询，导出 PDF

import re
from datetime import datetime, timedelta
from collections import defaultdict

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, FamilyBinding, Vitals, VitalDraftConversation, VitalAlert, FamilyMessage
from db.schemas import (
    VitalsCreate, VitalsOut, TrendPoint,
    VitalsSpokenParseRequest, VitalsSpokenDraftOut,
    VitalsSpokenTurnRequest, VitalsSpokenTurnOut, VitalAlertOut,
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


def _parse_measured_at(value: str | None):
    """把前端传来的日期/时间解析为 datetime；解析失败或为空时返回 None（用默认当前时间）。
    支持 'YYYY-MM-DD'、'YYYY-MM-DD HH:MM'、ISO 'YYYY-MM-DDTHH:MM:SS' 等格式。"""
    if not value:
        return None
    v = value.strip().replace("Z", "+00:00")
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(v, fmt)
        except ValueError:
            continue
    # 无法解析则忽略该字段，走默认时间
    return None


def resolve_elder_id(db: Session, current: User, elder_id: int | None) -> int:
    """解析目标数据归属：
    - 老人：总是操作自己的数据；
    - 家属：传 elder_id 则必须已绑定该老人；不传则操作自己的本人记录。
    10.26 起：家属读长辈体征/异常事件前，统一走 age.family_access_guard。
    """
    if current.role == "elder":
        return current.id
    if elder_id is None:
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
    allowed, reason = age_mod.family_access_guard(db, current, target_user)
    if not allowed:
        detail = {
            "birth_missing": "老人资料不完整（缺出生年月），请补全出生年月后再开放家属访问",
            "privacy_off": "老人未开启健康资料分享，家属暂不可见",
        }.get(reason, "无权访问该老人健康资料")
        raise HTTPException(status_code=403, detail=detail)
    return elder_id


def _maybe_create_alert(db: Session, vital: Vitals) -> None:
    """血压/血糖超阈值时写入可追踪事件，并向 active 绑定家属发送提示（内存推送记录）。

    10.26 起：家属推送前与读取端共用同一套年龄/隐私规则——
      - 满 60 周岁（senior）：强制推给所有 active 绑定家属；
      - 未满 60（younger）：仅当老人 sync_summary_to_family=True 时才推；
      - 出生年月缺失（unknown）：不推家属（与读取端 birth_missing 拒绝一致）。
    VitalAlert 记录始终写库供老人本人查看，不因隐私开关丢失。
    """
    ev = vth.evaluate(vital.type, vital.systolic, vital.diastolic, vital.value,
                      measurement_context=vital.measurement_context)
    if not ev or not ev["abnormal"]:
        return
    alert = VitalAlert(
        elder_id=vital.elder_id, vital_type=vital.type,
        systolic=vital.systolic, diastolic=vital.diastolic, value=vital.value,
        measurement_context=vital.measurement_context,
        level=ev["level"], message=ev["message"], source=ev["source"],
    )
    db.add(alert)
    db.commit()

    # 判断是否允许向家属推送（与 family_access_guard 读取规则一致）
    elder_user = db.query(User).filter(User.id == vital.elder_id).first()
    tier = age_mod.age_tier(elder_user.birth_ym if elder_user else None)
    allow_family_push = (tier == age_mod.TIER_SENIOR) or (
        tier == age_mod.TIER_YOUNGER and elder_user is not None
        and elder_user.sync_summary_to_family is not False
    )
    if not allow_family_push:
        return

    bindings = (
        db.query(FamilyBinding)
        .filter(FamilyBinding.elder_id == vital.elder_id,
                FamilyBinding.status == "active",
                FamilyBinding.family_id.isnot(None))
        .all()
    )
    for b in bindings:
        push_svc.send_push(b.family_id, "体征异常提醒",
                           f"老人体征异常提示（{ev['level']}）：{ev['message']}")
        db.add(FamilyMessage(
            binding_id=b.id, sender_id=vital.elder_id, kind="health",
            content={"type": "vital_alert", "alert_id": alert.id,
                     "vital_type": vital.type, "level": ev["level"],
                     "message": ev["message"], "source": ev["source"]},
        ))
    db.commit()


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
        measured_at=_parse_measured_at(payload.measured_at),
    )
    db.add(vital)
    db.commit()
    db.refresh(vital)
    _maybe_create_alert(db, vital)
    return vital


@router.get("/alerts", response_model=list[VitalAlertOut])
def list_vital_alerts(elder_id: int | None = None,
                      days: int = 90,
                      db: Session = Depends(get_db),
                      current: User = Depends(get_current_user)):
    """体征异常事件列表：老人本人看自己；绑定家属传 elder_id 看老人。仅提示，不替代诊断。"""
    target = resolve_elder_id(db, current, elder_id)
    cutoff = datetime.now() - timedelta(days=days)
    return (
        db.query(VitalAlert)
        .filter(VitalAlert.elder_id == target, VitalAlert.created_at >= cutoff)
        .order_by(VitalAlert.created_at.desc())
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
    cutoff = datetime.now() - timedelta(days=days)

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
    cutoff = datetime.now() - timedelta(days=days)

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
        day = r.measured_at.strftime("%Y-%m-%d") if r.measured_at else "unknown"
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
    cutoff = datetime.now() - timedelta(days=days)

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

    if payload.session_id:
        conv = db.get(VitalDraftConversation, payload.session_id)
        if not conv or conv.elder_id != elder_id:
            raise HTTPException(status_code=404, detail="体征会话不存在或无权访问")
        if conv.status in ("confirmed", "cancelled"):
            raise HTTPException(status_code=400, detail="该体征会话已结束，请重新发起")
    else:
        conv = VitalDraftConversation(elder_id=elder_id, status="collecting")
        db.add(conv)

    merge_turn(conv, payload.text, payload.hint_type)
    # measured_at 归一为 datetime（草稿解析器返回 ISO 字符串）
    if isinstance(conv.measured_at, str) and conv.measured_at:
        conv.measured_at = _parse_measured_at(conv.measured_at) or None
    db.commit()
    db.refresh(conv)

    return VitalsSpokenTurnOut(
        session_id=conv.id,
        status=conv.status,
        missing=list(conv.missing or []),
        question=conv.last_question or "",
        can_confirm=(conv.status == "ready"),
        draft=draft_payload(conv),
        disclaimer=HEALTH_DISCLAIMER,
    )


@router.post("/draft-conversations/{conv_id}/confirm", response_model=VitalsOut)
def confirm_vital_draft(conv_id: int,
                        db: Session = Depends(get_db),
                        current: User = Depends(get_current_user)):
    """确认体征会话：信息齐全且范围合法后，复用现有 POST /api/vitals 落库，并标记 confirmed。
    未确认（collecting）或字段缺失时拒绝写入。"""
    conv = db.get(VitalDraftConversation, conv_id)
    if not conv:
        raise HTTPException(status_code=404, detail="体征会话不存在")
    _conv_access_check(db, current, conv)
    if conv.status == "confirmed":
        raise HTTPException(status_code=400, detail="该体征会话已确认入库，不能重复确认")
    if conv.status == "cancelled":
        raise HTTPException(status_code=400, detail="该体征会话已取消，无法确认")
    if conv.status != "ready":
        raise HTTPException(status_code=400, detail="信息尚未齐全，无法确认")

    missing = compute_missing(conv)
    if missing:
        raise HTTPException(status_code=400, detail=f"仍有缺失字段：{missing}，请先补齐")
    errors = _revalidate(conv)
    if errors:
        raise HTTPException(status_code=400, detail=errors[0])

    measured_at = conv.measured_at
    if isinstance(measured_at, datetime):
        measured_at = measured_at.strftime("%Y-%m-%d %H:%M:%S")
    payload = VitalsCreate(
        type=conv.type,
        systolic=conv.systolic,
        diastolic=conv.diastolic,
        value=conv.value,
        measurement_context=conv.measurement_context or "unknown",
        measured_at=measured_at or None,
        elder_id=conv.elder_id,
    )
    # 复用现有 create_vital：范围校验、老人/家属归属、measured_at 解析、落库全部一致
    out = create_vital(payload, db, current)
    conv.status = "confirmed"
    db.commit()
    return out


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
        raise HTTPException(status_code=400, detail="该会话已确认入库，不能取消")
    conv.status = "cancelled"
    db.commit()
    return {"ok": True}


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

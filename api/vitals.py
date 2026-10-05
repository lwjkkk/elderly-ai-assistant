# 体征接口：录入血压/血糖/心率/体重，按天聚合趋势查询，导出 PDF

import re
from datetime import datetime, timedelta
from collections import defaultdict

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, FamilyBinding, Vitals
from db.schemas import (
    VitalsCreate, VitalsOut, VitalsRecognizeRequest, VitalsRecognizeOut, TrendPoint,
)
from core.security import get_current_user
from core.disclaimer import HEALTH_DISCLAIMER
from core.ocr import recognize_image
from core.qwen_llm import call_qwen
from services.pdf_export import generate_vitals_pdf

router = APIRouter(prefix="/api/vitals", tags=["体征"])

VALID_TYPES = {"bp", "bs", "hr", "weight"}


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
    """解析目标老人：老人默认自己；家属必须显式指定且已绑定。"""
    if current.role == "elder":
        return current.id
    if elder_id is None:
        raise HTTPException(status_code=400, detail="家属操作需指定 elder_id")
    binding = (
        db.query(FamilyBinding)
        .filter(FamilyBinding.elder_id == elder_id)
        .filter(FamilyBinding.family_id == current.id)
        .filter(FamilyBinding.status == "active")
        .first()
    )
    if not binding:
        raise HTTPException(status_code=403, detail="未绑定该老人，无权操作")
    return elder_id


@router.post("", response_model=VitalsOut)
def create_vital(payload: VitalsCreate,
                 db: Session = Depends(get_db),
                 current: User = Depends(get_current_user)):
    """录入一条体征记录。"""
    if payload.type not in VALID_TYPES:
        raise HTTPException(status_code=400, detail=f"类型只能是 {VALID_TYPES}")

    # 血压必须同时有收缩压和舒张压
    if payload.type == "bp" and (payload.systolic is None or payload.diastolic is None):
        raise HTTPException(status_code=400, detail="血压需同时填写收缩压和舒张压")

    elder_id = resolve_elder_id(db, current, payload.elder_id)

    vital = Vitals(
        elder_id=elder_id,
        type=payload.type,
        systolic=payload.systolic,
        diastolic=payload.diastolic,
        value=payload.value,
        measured_at=_parse_measured_at(payload.measured_at),
    )
    db.add(vital)
    db.commit()
    db.refresh(vital)
    return vital


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

    elder = db.query(User).filter(User.id == target).first()
    pdf_bytes = generate_vitals_pdf(records, elder.nickname if elder else "老人", HEALTH_DISCLAIMER)

    return StreamingResponse(
        iter([pdf_bytes]),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=vitals_{target}.pdf"},
    )


# 体征识别提示词：解析测量设备屏幕/照片上的数值，只输出固定结构
VITALS_RECOGNIZE_PROMPT = (
    "你是体征识别助手。根据测量设备（血压计/血糖仪/心率表/体重秤）照片识别到的文字，"
    "提取体征数值。只输出以下格式，没有的字段省略，不要解释：\n"
    "TYPE: bp 或 bs 或 hr 或 weight（血压/血糖/心率/体重）\n"
    "SYSTOLIC: 收缩压（仅血压）\n"
    "DIASTOLIC: 舒张压（仅血压）\n"
    "VALUE: 数值（血糖/心率/体重）\n"
    "UNIT: 单位（如 mmHg / mmol/L / bpm / kg）\n"
    "如果识别不出有效体征数值，只输出：NONE"
)


@router.post("/recognize", response_model=VitalsRecognizeOut)
def recognize_vital(payload: VitalsRecognizeRequest,
                    current: User = Depends(get_current_user)):
    """体征拍照识别：血压计/血糖仪照片 → 数值。识别结果不落库，
    前端展示给老人确认后，再调 POST /api/vitals 落库。"""
    try:
        ocr_text = recognize_image(payload.image_base64)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception:
        raise HTTPException(status_code=400, detail="图片识别失败，请重新拍摄清晰的设备屏幕再试")

    if not ocr_text.strip():
        raise HTTPException(status_code=400, detail="未识别到文字，请拍清楚测量仪屏幕")

    llm_out = call_qwen(
        VITALS_RECOGNIZE_PROMPT,
        f"识别到的文字如下：\n{ocr_text}",
    )
    if "NONE" in llm_out.upper():
        raise HTTPException(status_code=400, detail="未能从照片中识别出有效体征数值")

    parsed = _parse_vitals_llm(llm_out, payload.vital_type)
    if parsed is None:
        raise HTTPException(status_code=400, detail="识别结果异常，请人工确认后手动录入")

    parsed["raw_text"] = ocr_text
    return VitalsRecognizeOut(**parsed)


def _parse_vitals_llm(text: str, hint_type: str | None) -> dict | None:
    """从 LLM 输出里提取体征字段。血压必须有收缩压+舒张压；其他必须有 value。"""
    def _gint(p):
        m = re.search(rf"{p}[:：]\s*([+-]?\d+)", text)
        return int(m.group(1)) if m else None

    def _gfloat(p):
        m = re.search(rf"{p}[:：]\s*([+-]?\d+(?:\.\d+)?)", text)
        return float(m.group(1)) if m else None

    t = hint_type or "bp"  # 默认按血压解析
    m_type = re.search(r"TYPE[:：]\s*(\w+)", text)
    if m_type:
        t = m_type.group(1).strip().lower()
        if t not in VALID_TYPES:
            t = hint_type or "bp"

    result = {"type": t, "systolic": None, "diastolic": None, "value": None, "unit": None}
    m_unit = re.search(r"UNIT[:：]\s*(\S+)", text)
    if m_unit:
        result["unit"] = m_unit.group(1).strip()

    if t == "bp":
        sys, dia = _gint("SYSTOLIC"), _gint("DIASTOLIC")
        if sys is None or dia is None:
            return None
        result["systolic"], result["diastolic"] = sys, dia
    else:
        val = _gfloat("VALUE")
        if val is None:
            return None
        result["value"] = val
    return result

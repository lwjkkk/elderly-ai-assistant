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
from core.ocr import recognize_image, OcrUnavailableError
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
    """解析目标数据归属：
    - 老人：总是操作自己的数据；
    - 家属：传 elder_id 则必须已绑定该老人；不传则操作自己的本人记录。
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


# 体征识别提示词：解析测量设备屏幕/照片上的数值，只输出固定结构
VITALS_RECOGNIZE_PROMPT = (
    "你是体征识别助手。根据测量设备（血压计/血糖仪/心率表/体重秤）照片识别到的文字，"
    "提取体征数值。只输出以下格式，没有的字段省略，不要解释：\n"
    "TYPE: bp 或 bs 或 hr 或 weight（血压/血糖/心率/体重）\n"
    "SYSTOLIC: 收缩压（仅血压）\n"
    "DIASTOLIC: 舒张压（仅血压）\n"
    "VALUE: 数值（血糖/心率/体重）\n"
    "UNIT: 原始单位（如 mmHg / mmol/L / mg/dL / bpm / kg）\n"
    "CONFIDENCE: 识别置信度，0 到 1 之间的小数（如 0.92）\n"
    "如果识别不出有效体征数值，只输出：NONE"
)


@router.post("/recognize", response_model=VitalsRecognizeOut)
def recognize_vital(payload: VitalsRecognizeRequest,
                    db: Session = Depends(get_db),
                    current: User = Depends(get_current_user)):
    """体征拍照识别：血压计/血糖仪/体重秤/心率表照片 → 数值。
    识别结果不落库，前端展示给老人确认后，再调 POST /api/vitals 落库。"""
    # 沿用老人/家属归属校验（家属需绑定，老人默认自己）
    resolve_elder_id(db, current, payload.elder_id)

    try:
        ocr_text = recognize_image(payload.image_base64)
    except OcrUnavailableError as e:
        raise HTTPException(status_code=500, detail=f"识别服务暂不可用，请稍后再试：{e}")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    llm_out = call_qwen(
        VITALS_RECOGNIZE_PROMPT,
        f"识别到的文字如下：\n{ocr_text}",
    )
    # 只有整段输出就是 NONE（识别失败）才算失败；
    # 血压场景下 LLM 会写 VALUE: NONE（该字段不适用），不能被子串误判。
    if llm_out.strip().upper() == "NONE":
        raise HTTPException(status_code=400, detail="照片中未识别到体征数值，请重拍一张清晰的")

    parsed = _parse_vitals_llm(llm_out, payload.vital_type)
    if parsed is None:
        raise HTTPException(status_code=400, detail="照片中未识别到体征数值，请重拍一张清晰的")

    parsed["ocr_text"] = ocr_text
    return VitalsRecognizeOut(**parsed)


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

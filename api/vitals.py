# 体征接口：录入血压/血糖/心率/体重，按天聚合趋势查询，导出 PDF

from datetime import datetime, timedelta
from collections import defaultdict

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, FamilyBinding, Vitals
from db.schemas import VitalsCreate, VitalsOut, TrendPoint
from core.security import get_current_user
from core.disclaimer import HEALTH_DISCLAIMER
from services.pdf_export import generate_vitals_pdf

router = APIRouter(prefix="/api/vitals", tags=["体征"])

VALID_TYPES = {"bp", "bs", "hr", "weight"}


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

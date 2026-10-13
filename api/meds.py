# 用药接口：药品增删改查、今日用药清单、服药打卡
# 权限：老人管理自己的药；家属只能操作已绑定老人的药（可代录、查看打卡状态）

from datetime import datetime, timedelta, timezone
import re

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, FamilyBinding, Medication, MedicationLog
from db.schemas import (
    MedicationCreate, MedicationUpdate, MedicationOut, CheckInRequest, LogOut, TodayMedication, SlotStatus,
)
from core.security import get_current_user

router = APIRouter(prefix="/api/meds", tags=["用药"])

_SHANGHAI = timezone(timedelta(hours=8))


def _checkin_time(med: Medication, slot: str, date: str | None) -> str:
    """以北京时间校验计划日期和时间，客户端不能提前打卡。"""
    now = datetime.now(_SHANGHAI)
    day = date or now.strftime("%Y-%m-%d")
    if slot not in med.times or not re.fullmatch(r"\d{2}:\d{2}", slot):
        raise HTTPException(status_code=400, detail="该时间点不在用药计划中")
    try:
        scheduled = datetime.strptime(f"{day} {slot}", "%Y-%m-%d %H:%M").replace(tzinfo=_SHANGHAI)
    except ValueError:
        raise HTTPException(status_code=400, detail="日期或服药时间格式不正确")
    if med.start_date and day < med.start_date:
        raise HTTPException(status_code=400, detail="尚未到开始用药日期")
    if scheduled > now:
        raise HTTPException(status_code=400, detail="尚未到服药时间，请到时间后再打卡")
    return day


def assert_can_access(db: Session, current: User, elder_id: int) -> int:
    """校验当前用户是否有权操作该老人的数据，返回 elder_id；无权则 403。"""
    # 老人本人或家属本人记录都归当前账号所有，不需要绑定关系。
    if elder_id == current.id:
        return elder_id
    if current.role == "elder":
        if elder_id != current.id:
            raise HTTPException(status_code=403, detail="只能操作自己的数据")
        return elder_id

    # 家属：必须与该老人有 active 绑定
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


def resolve_elder_id(db: Session, current: User, elder_id: int | None) -> int:
    """解析目标数据归属：
    - 老人：总是操作自己的数据（忽略传入的 elder_id）；
    - 家属：传 elder_id 则必须已绑定该老人（代录/查看长辈）；不传则操作自己的本人记录。
    """
    if current.role == "elder":
        return assert_can_access(db, current, current.id)
    if elder_id is None:
        # 家属本人区：管理自己的体征/报告/录音等记录
        return current.id
    return assert_can_access(db, current, elder_id)


@router.post("", response_model=MedicationOut)
def create_med(payload: MedicationCreate,
               db: Session = Depends(get_db),
               current: User = Depends(get_current_user)):
    """录入药品（老人自己录，或家属代老人录）。"""
    if not payload.times:
        raise HTTPException(status_code=400, detail="至少设置一个服药时间点")
    elder_id = resolve_elder_id(db, current, payload.elder_id)

    med = Medication(
        elder_id=elder_id,
        created_by=current.id,
        name=payload.name,
        dosage=payload.dosage,
        frequency=payload.frequency,
        times=payload.times,
        start_date=payload.start_date,
    )
    db.add(med)
    db.commit()
    db.refresh(med)
    return med


@router.get("", response_model=list[MedicationOut])
def list_meds(elder_id: int | None = None,
              db: Session = Depends(get_db),
              current: User = Depends(get_current_user)):
    """药品列表：老人看自己；家属传 elder_id 看绑定老人。"""
    target = resolve_elder_id(db, current, elder_id)
    return db.query(Medication).filter(Medication.elder_id == target).all()


@router.put("/{med_id}", response_model=MedicationOut)
def update_med(med_id: int, payload: MedicationUpdate,
               db: Session = Depends(get_db),
               current: User = Depends(get_current_user)):
    """修改药品信息（只更新传入的字段）。"""
    med = db.query(Medication).filter(Medication.id == med_id).first()
    if not med:
        raise HTTPException(status_code=404, detail="药品不存在")
    assert_can_access(db, current, med.elder_id)

    if payload.name is not None:
        med.name = payload.name
    if payload.dosage is not None:
        med.dosage = payload.dosage
    if payload.frequency is not None:
        med.frequency = payload.frequency
    if payload.times is not None:
        if not payload.times:
            raise HTTPException(status_code=400, detail="至少设置一个服药时间点")
        med.times = payload.times
    if payload.start_date is not None:
        med.start_date = payload.start_date
    db.commit()
    db.refresh(med)
    return med


@router.delete("/{med_id}")
def delete_med(med_id: int,
               db: Session = Depends(get_db),
               current: User = Depends(get_current_user)):
    """删除药品（同时删除其打卡记录）。"""
    med = db.query(Medication).filter(Medication.id == med_id).first()
    if not med:
        raise HTTPException(status_code=404, detail="药品不存在")
    assert_can_access(db, current, med.elder_id)

    db.query(MedicationLog).filter(MedicationLog.medication_id == med_id).delete()
    db.delete(med)
    db.commit()
    return {"detail": "已删除"}


@router.get("/today", response_model=list[TodayMedication])
def today_meds(elder_id: int | None = None,
               date: str | None = None,
               db: Session = Depends(get_db),
               current: User = Depends(get_current_user)):
    """今日用药清单：每个药品展开时间点及状态（未打卡为 pending）。"""
    target = resolve_elder_id(db, current, elder_id)
    date = date or datetime.now(_SHANGHAI).strftime("%Y-%m-%d")

    meds = db.query(Medication).filter(Medication.elder_id == target).all()
    result = []
    for med in meds:
        if med.start_date and date < med.start_date:
            continue
        slots = []
        for slot in med.times:
            log = (
                db.query(MedicationLog)
                .filter(MedicationLog.medication_id == med.id)
                .filter(MedicationLog.date == date)
                .filter(MedicationLog.slot == slot)
                .first()
            )
            slots.append(SlotStatus(slot=slot, status=log.status if log else "pending"))
        result.append(TodayMedication(
            medication_id=med.id, name=med.name, dosage=med.dosage, slots=slots))
    return result


@router.post("/checkin", response_model=LogOut)
def check_in(payload: CheckInRequest,
             db: Session = Depends(get_db),
             current: User = Depends(get_current_user)):
    """标记已服药：在 medication_logs 中写入/更新 taken。"""
    med = db.query(Medication).filter(Medication.id == payload.medication_id).first()
    if not med:
        raise HTTPException(status_code=404, detail="药品不存在")
    assert_can_access(db, current, med.elder_id)

    date = _checkin_time(med, payload.slot, payload.date)
    log = (
        db.query(MedicationLog)
        .filter(MedicationLog.medication_id == med.id)
        .filter(MedicationLog.date == date)
        .filter(MedicationLog.slot == payload.slot)
        .first()
    )
    if not log:
        log = MedicationLog(
            medication_id=med.id, elder_id=med.elder_id,
            date=date, slot=payload.slot, status="taken")
        db.add(log)
    else:
        log.status = "taken"
    db.commit()
    db.refresh(log)
    return log

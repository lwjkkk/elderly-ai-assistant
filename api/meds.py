# 用药接口：药品增删改查、今日用药清单、服药打卡
# 权限：老人管理自己的药；家属只能操作已绑定老人的药（可代录、查看打卡状态）

from datetime import datetime, timedelta, timezone
import re

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from db.database import get_db
from db.models import User, FamilyBinding, Medication, MedicationLog
from db.schemas import (
    MedicationCreate, MedicationUpdate, MedicationOut, CheckInRequest, LogOut, TodayMedication, SlotStatus,
)
from core.security import get_current_user
from core import age as age_mod
from config.settings import MEDICATION_CHECKIN_GRACE_MINUTES

router = APIRouter(prefix="/api/meds", tags=["用药"])

_SHANGHAI = timezone(timedelta(hours=8))
_TIME_RE = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")
_DATE_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$")


def _validate_times(times: list[str]) -> None:
    """校验服药时间点：必须是 HH:MM（00:00~23:59），不允许重复。"""
    if not times:
        raise HTTPException(status_code=400, detail="至少设置一个服药时间点")
    seen = set()
    for t in times:
        t = (t or "").strip()
        if not _TIME_RE.match(t):
            raise HTTPException(status_code=400, detail=f"服药时间格式无效：{t}，应为 HH:MM（00:00~23:59）")
        if t in seen:
            raise HTTPException(status_code=400, detail=f"服药时间重复：{t}")
        seen.add(t)


def _validate_start_date(sd: str | None) -> None:
    """校验开始日期：传了就必须是真实存在的 YYYY-MM-DD 日历日期；None/空串视为不设置或清除。
    仅靠正则会放过 2026-02-31 这种不存在的日期，必须用 strptime 二次校验。"""
    if not sd:
        return
    if not _DATE_RE.match(sd):
        raise HTTPException(status_code=400, detail=f"开始日期格式无效：{sd}，应为 YYYY-MM-DD")
    try:
        datetime.strptime(sd, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail=f"开始日期不存在：{sd}，请检查月份和日期")


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
    if now - scheduled > timedelta(minutes=MEDICATION_CHECKIN_GRACE_MINUTES):
        raise HTTPException(status_code=400, detail="已超过服药时间1小时，本次打卡已关闭；未打卡不代表实际未服药")
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
    - 老人：只能操作自己的数据；
    - 家属：传 elder_id 则必须已绑定该老人（代录/查看长辈），不传则操作自己的本人记录。
    10.26 起：家属读取长辈健康资料前，统一走 age.family_access_guard
    （绑定校验 + birth_ym 完整性 + senior 强制分享 / younger 按开关），
    与 /api/sync 同一套规则。
    """
    if current.role == "elder":
        if elder_id is not None and elder_id != current.id:
            raise HTTPException(status_code=403, detail="只能操作自己的数据")
        return assert_can_access(db, current, current.id)
    if elder_id is None:
        # 家属本人区：管理自己的体征/报告/录音等记录
        return current.id
    target = assert_can_access(db, current, elder_id)
    # 家属读长辈资料：统一年龄/隐私闸门（本人访问已在 family_access_guard 内放行）
    target_user = db.query(User).filter(User.id == target).first()
    allowed, reason = age_mod.family_access_guard(db, current, target_user)
    if not allowed:
        detail = {
            "birth_missing": "老人资料不完整（缺出生年月），请补全出生年月后再开放家属访问",
            "privacy_off": "老人未开启健康资料分享，家属暂不可见",
            "not_binding": "未绑定该老人",
        }.get(reason, "无权访问该老人健康资料")
        raise HTTPException(status_code=403, detail=detail)
    return target


@router.post("", response_model=MedicationOut)
def create_med(payload: MedicationCreate,
               db: Session = Depends(get_db),
               current: User = Depends(get_current_user)):
    """录入药品（老人自己录，或家属代老人录）。times 表示每天这些时间点提醒。"""
    _validate_times(payload.times)
    _validate_start_date(payload.start_date)
    elder_id = resolve_elder_id(db, current, payload.elder_id)

    med = Medication(
        elder_id=elder_id,
        created_by=current.id,
        name=payload.name,
        dosage=payload.dosage,
        frequency=payload.frequency,
        times=[slot.strip() for slot in payload.times],
        start_date=payload.start_date or None,
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
        _validate_times(payload.times)
        med.times = [slot.strip() for slot in payload.times]
    if payload.clear_start_date:
        med.start_date = None
    elif payload.start_date is not None:
        _validate_start_date(payload.start_date)
        med.start_date = payload.start_date or None
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


@router.get("/reminder-policy")
def reminder_policy(current: User = Depends(get_current_user)):
    """Server policy/capability only; never infers Android permissions or delivery."""
    from services.push import capabilities
    return {"timezone": "Asia/Shanghai", "checkin_grace_minutes": MEDICATION_CHECKIN_GRACE_MINUTES,
            "checkin_deadline_inclusive": True, "missed_means": "未在时限内打卡，不证明实际未服药",
            "local_reminder": {"managed_by": "app", "permission_status": "unknown_to_server",
                               "exact_alarm_status": "unknown_to_server"},
            "remote_push": capabilities()}


@router.get("/today", response_model=list[TodayMedication])
def today_meds(elder_id: int | None = None,
               date: str | None = None,
               db: Session = Depends(get_db),
               current: User = Depends(get_current_user)):
    """今日用药清单：每个药品展开时间点及状态（未打卡为 pending）。"""
    target = resolve_elder_id(db, current, elder_id)
    date = date or datetime.now(_SHANGHAI).strftime("%Y-%m-%d")
    _validate_start_date(date)

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
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        # Another request/scan may have created the unique medication/date/slot.
        log = db.query(MedicationLog).filter_by(
            medication_id=med.id, date=date, slot=payload.slot).first()
        if log is None:
            raise
        log.status = "taken"
        db.commit()
    db.refresh(log)
    return log

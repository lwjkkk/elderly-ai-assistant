# 定时任务：到点推送用药提醒、超时未打卡判定漏服
# 核心逻辑写成纯函数（可直接调用做测试），APScheduler 负责每分钟触发。
# 幂等保证：
#   1. medication_logs 表有 (medication_id, date, slot) 唯一约束；
#   2. _get_or_create_log 用 IntegrityError 兜底，多进程并发插入时一方回退为重查；
#   3. start_scheduler() 用文件锁保证多 worker 部署时只有一个进程跑定时任务。

import logging
import os
import re
from datetime import datetime, timedelta, timezone

from sqlalchemy.exc import IntegrityError
from sqlalchemy import text

from db.database import SessionLocal, engine
from db.models import Medication, MedicationLog, NotificationOutbox
from services.medication_notifications import stage
from config.settings import MEDICATION_CHECKIN_GRACE_MINUTES

logger = logging.getLogger(__name__)

# 超过服药时间多少分钟仍未打卡，判定为漏服
GRACE_MINUTES = MEDICATION_CHECKIN_GRACE_MINUTES

_scheduler = None
_LOCK_PATH = os.path.join(os.path.dirname(__file__), ".scheduler.lock")


def _slots(med):
    """Malformed legacy schedules must not stop reminders for all other records."""
    if not isinstance(med.times, list):
        logger.warning("跳过无效用药时间列表 medication_id=%s", med.id)
        return []
    slots = []
    for value in med.times:
        if not isinstance(value, str) or not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value):
            logger.warning("跳过无效用药时间点 medication_id=%s", med.id)
            continue
        if value not in slots:
            slots.append(value)
    return slots


def _beijing_now(now: datetime | None = None) -> datetime:
    """统一以北京时间（UTC+8）为准，兼容传入带 tz 的时间对象。"""
    zone = timezone(timedelta(hours=8))
    value = now or datetime.now(zone)
    if value.tzinfo is not None:
        value = value.astimezone(zone).replace(tzinfo=None)
    return value


def _get_or_create_log(db, med: Medication, date: str, slot: str, status: str) -> MedicationLog:
    """查找某药品某天某时间点的记录，没有则按给定状态创建。
    并发下两个进程同时插入会撞唯一约束；catch 后回退为重查并更新状态。"""
    log = (
        db.query(MedicationLog)
        .filter(MedicationLog.medication_id == med.id)
        .filter(MedicationLog.date == date)
        .filter(MedicationLog.slot == slot)
        .first()
    )
    if log:
        return log
    log = MedicationLog(
        medication_id=med.id, elder_id=med.elder_id,
        date=date, slot=slot, status=status)
    try:
        with db.begin_nested():
            db.add(log)
            db.flush()
    except IntegrityError:
        log = (
            db.query(MedicationLog)
            .filter(MedicationLog.medication_id == med.id)
            .filter(MedicationLog.date == date)
            .filter(MedicationLog.slot == slot)
            .first()
        )
    return log


def run_reminder_cycle(now: datetime | None = None) -> list[dict]:
    """Persist due notices before dispatch, catching up within the check-in window."""
    now = _beijing_now(now)
    ids = []
    db = SessionLocal()
    try:
        if db.bind.dialect.name == "sqlite":
            # Keep SAVEPOINT releases inside a real parent transaction on sqlite3.
            db.execute(text("BEGIN IMMEDIATE"))
        for med in db.query(Medication).all():
            for offset in (1, 0):
                day = (now-timedelta(days=offset)).strftime("%Y-%m-%d")
                if med.start_date and day < med.start_date:
                    continue
                for slot in _slots(med):
                    due = datetime.strptime(day+" "+slot, "%Y-%m-%d %H:%M")
                    if not timedelta(0) <= now-due <= timedelta(minutes=GRACE_MINUTES):
                        continue
                    log = _get_or_create_log(db, med, day, slot, "pending")
                    if log.status == "pending":
                        ids.extend(stage(db,med,day,slot,"medication_due",GRACE_MINUTES))
        db.commit()
    finally:
        db.close()
    _dispatch(now)
    with SessionLocal() as db:
        return [{"receiver_id":row.receiver_id, "title":row.title, "content":row.content,
                 "status":row.status, "channel":row.channel}
                for row in db.query(NotificationOutbox).filter(NotificationOutbox.id.in_(ids)).all()]


def _dispatch(now):
    # A transport failure must not roll back persisted schedules/cards or other meds.
    from services.notification_outbox import process_pending
    try:
        return process_pending(SessionLocal, now=now.replace(tzinfo=timezone(timedelta(hours=8))))
    except Exception:
        logger.exception("用药通知派发失败；已提交的记录保留，等待后续任务重试")
        return None


def run_missed_cycle(now: datetime | None = None, grace: int = GRACE_MINUTES) -> list[dict]:
    """Mark missing check-ins, not proof of missed doses. Includes midnight rollover."""
    now = _beijing_now(now)
    db = SessionLocal()
    missed = []
    try:
        if db.bind.dialect.name == "sqlite":
            db.execute(text("BEGIN IMMEDIATE"))
        for med in db.query(Medication).all():
            for offset in (1, 0):
                day = (now-timedelta(days=offset)).strftime("%Y-%m-%d")
                if med.start_date and day < med.start_date:
                    continue
                for slot in _slots(med):
                    due = datetime.strptime(day+" "+slot, "%Y-%m-%d %H:%M")
                    if offset and (due+timedelta(minutes=grace)).date() < now.date():
                        continue  # Yesterday is only for windows that cross midnight, not bulk backfill.
                    if now-due <= timedelta(minutes=grace):
                        continue
                    log = _get_or_create_log(db,med,day,slot,"pending")
                    # Conditional update serializes with a competing taken check-in.
                    changed = db.query(MedicationLog).filter_by(id=log.id,status="pending").update(
                        {"status":"missed"},synchronize_session=False)
                    if not changed:
                        continue
                    db.flush()
                    stage(db,med,day,slot,"medication_missed",grace)
                    missed.append({"medication_id":med.id,"date":day,"slot":slot,"status":"missed"})
        db.commit()
    finally:
        db.close()
    _dispatch(now)
    return missed


def run_notification_outbox_cycle() -> dict:
    """Retry durable health notification attempts independently from health writes."""
    from services.notification_outbox import process_pending
    return process_pending(SessionLocal)


def start_scheduler():
    """启动 APScheduler 后台定时任务（懒加载，未安装则跳过）。
    多 worker 部署时通过环境变量 RUN_SCHEDULER=1 指定唯一一个 worker 跑；
    未设置时默认启动（单进程开发/演示模式向后兼容）。"""
    global _scheduler
    if _scheduler is not None:
        return _scheduler
    flag = os.getenv("RUN_SCHEDULER", "1").strip()
    if flag in ("0", "false", "False", "no"):
        logger.info("RUN_SCHEDULER=%s，本进程不启动定时任务", flag)
        return None
    try:
        from apscheduler.schedulers.background import BackgroundScheduler
    except ImportError:
        logger.warning("未安装 apscheduler，定时任务未启动（pip install apscheduler）")
        return None

    s = BackgroundScheduler()
    s.add_job(run_reminder_cycle, "cron", minute="*")          # 每分钟检查提醒
    s.add_job(run_missed_cycle, "cron", minute="*/5")          # 每5分钟检查漏服
    s.add_job(run_notification_outbox_cycle, "interval", minutes=1,
              id="notification_outbox", replace_existing=True)
    s.start()
    _scheduler = s
    logger.info("用药定时任务已启动")
    return s

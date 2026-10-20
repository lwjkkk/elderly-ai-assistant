# 定时任务：到点推送用药提醒、超时未打卡判定漏服
# 核心逻辑写成纯函数（可直接调用做测试），APScheduler 负责每分钟触发。
# 幂等保证：
#   1. medication_logs 表有 (medication_id, date, slot) 唯一约束；
#   2. _get_or_create_log 用 IntegrityError 兜底，多进程并发插入时一方回退为重查；
#   3. start_scheduler() 用文件锁保证多 worker 部署时只有一个进程跑定时任务。

import logging
import os
from datetime import datetime, timedelta, timezone

from sqlalchemy.exc import IntegrityError

from db.database import SessionLocal, engine
from db.models import Medication, MedicationLog, FamilyBinding
from services import push

logger = logging.getLogger(__name__)

# 超过服药时间多少分钟仍未打卡，判定为漏服
GRACE_MINUTES = 30

_scheduler = None
_LOCK_PATH = os.path.join(os.path.dirname(__file__), ".scheduler.lock")


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
    db.add(log)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        log = (
            db.query(MedicationLog)
            .filter(MedicationLog.medication_id == med.id)
            .filter(MedicationLog.date == date)
            .filter(MedicationLog.slot == slot)
            .first()
        )
    return log


def run_reminder_cycle(now: datetime | None = None) -> list[dict]:
    """扫描当前分钟应服用的药，推送提醒给老人和绑定家属。"""
    now = _beijing_now(now)
    date = now.strftime("%Y-%m-%d")
    hm = now.strftime("%H:%M")

    db = SessionLocal()
    pushed = []
    try:
        meds = db.query(Medication).all()
        for med in meds:
            if med.start_date and date < med.start_date:
                continue
            if hm not in med.times:
                continue
            # 已推送过则跳过，避免同一分钟内重复推送
            existing_log = (
                db.query(MedicationLog)
                .filter(MedicationLog.medication_id == med.id)
                .filter(MedicationLog.date == date)
                .filter(MedicationLog.slot == hm)
                .first()
            )
            if existing_log:
                continue
            _get_or_create_log(db, med, date, hm, "pending")
            msg = f"该服用 {med.name}（{med.dosage}）了"
            pushed.append(push.send_push(med.elder_id, "用药提醒", msg))
            # 同步通知所有绑定家属
            bindings = (
                db.query(FamilyBinding)
                .filter(FamilyBinding.elder_id == med.elder_id)
                .filter(FamilyBinding.status == "active")
                .all()
            )
            for b in bindings:
                pushed.append(push.send_push(b.family_id, "老人用药提醒", msg))
        db.commit()
    finally:
        db.close()
    return pushed


def run_missed_cycle(now: datetime | None = None, grace: int = GRACE_MINUTES) -> list[dict]:
    """把已过宽限期仍未打卡的时间点标记为漏服。"""
    now = _beijing_now(now)
    date = now.strftime("%Y-%m-%d")
    hm = now.strftime("%H:%M")

    db = SessionLocal()
    missed = []
    try:
        meds = db.query(Medication).all()
        for med in meds:
            if med.start_date and date < med.start_date:
                continue
            for slot in med.times:
                # HH:MM 字符串可直接比较先后；只处理今天已过的时间点
                if slot >= hm:
                    continue
                log = (
                    db.query(MedicationLog)
                    .filter(MedicationLog.medication_id == med.id)
                    .filter(MedicationLog.date == date)
                    .filter(MedicationLog.slot == slot)
                    .first()
                )
                if log and log.status != "pending":
                    continue  # 已服或已处理过

                hour, minute = map(int, slot.split(":"))
                due = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
                if now - due <= timedelta(minutes=grace):
                    continue  # 还在宽限期内

                if log:
                    log.status = "missed"
                else:
                    log = MedicationLog(
                        medication_id=med.id, elder_id=med.elder_id,
                        date=date, slot=slot, status="missed")
                    db.add(log)
                missed.append({"medication_id": med.id, "slot": slot, "status": "missed"})
        db.commit()
    finally:
        db.close()
    return missed


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
    s.start()
    _scheduler = s
    logger.info("用药定时任务已启动")
    return s

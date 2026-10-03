# 增量同步接口：家属端（或老人换设备）按时间戳拉取老人的全部健康数据
# 用法：GET /api/sync?elder_id=1&since=2026-10-02T00:00:00
# 首次同步不传 since，返回全量；之后传上次响应里的 server_time 做增量。

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import (
    User, Medication, MedicationLog, Vitals, HealthReport, SymptomCheck, ConsultRecord,
)
from db.schemas import (
    MedicationOut, LogOut, VitalsOut, HealthReportOut, SymptomOut, ConsultOut,
)
from core.security import get_current_user
from api.meds import resolve_elder_id

router = APIRouter(prefix="/api", tags=["同步"])


def _parse_since(since: str | None) -> datetime | None:
    """把 ISO 时间解析为朴素 UTC（SQLite 里存的就是朴素 UTC）。"""
    if not since:
        return None
    try:
        dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


@router.get("/sync")
def sync(since: str | None = None,
         elder_id: int | None = None,
         db: Session = Depends(get_db),
         current: User = Depends(get_current_user)):
    """增量拉取某位老人自 since 以来变更的健康数据。"""
    target = resolve_elder_id(db, current, elder_id)
    ts = _parse_since(since)

    # 药品：按创建时间
    q_med = db.query(Medication).filter(Medication.elder_id == target)
    if ts:
        q_med = q_med.filter(Medication.created_at >= ts)
    meds = q_med.all()

    # 服药记录：按更新时间（打卡会刷新 updated_at）
    q_log = db.query(MedicationLog).filter(MedicationLog.elder_id == target)
    if ts:
        q_log = q_log.filter(MedicationLog.updated_at >= ts)
    logs = q_log.all()

    # 体征：按测量时间
    q_vit = db.query(Vitals).filter(Vitals.elder_id == target)
    if ts:
        q_vit = q_vit.filter(Vitals.measured_at >= ts)
    vitals = q_vit.all()

    # 体检报告
    q_rep = db.query(HealthReport).filter(HealthReport.elder_id == target)
    if ts:
        q_rep = q_rep.filter(HealthReport.created_at >= ts)
    reports = q_rep.all()

    # 症状自查
    q_sym = db.query(SymptomCheck).filter(SymptomCheck.elder_id == target)
    if ts:
        q_sym = q_sym.filter(SymptomCheck.created_at >= ts)
    symptoms = q_sym.all()

    # 问诊录音
    q_con = db.query(ConsultRecord).filter(ConsultRecord.elder_id == target)
    if ts:
        q_con = q_con.filter(ConsultRecord.created_at >= ts)
    consults = q_con.all()

    server_time = datetime.now(timezone.utc).replace(microsecond=0)

    return {
        "server_time": server_time.isoformat(),
        "elder_id": target,
        "medications": [MedicationOut.model_validate(m).model_dump() for m in meds],
        "medication_logs": [LogOut.model_validate(l).model_dump() for l in logs],
        "vitals": [VitalsOut.model_validate(v).model_dump() for v in vitals],
        "reports": [HealthReportOut.model_validate(r).model_dump() for r in reports],
        "symptoms": [SymptomOut.model_validate(s).model_dump() for s in symptoms],
        "consults": [ConsultOut.model_validate(c).model_dump() for c in consults],
    }

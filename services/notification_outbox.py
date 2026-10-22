"""Persistent outbox dispatch for health-alert notifications.

Database writes happen before this module calls an external adapter. A provider
acceptance is recorded as ``submitted``; the in-memory adapter is only
``recorded`` and never represented as a delivered phone notification.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import or_, and_, update

from db.models import NotificationOutbox, User, FamilyBinding, VitalAlert, Vitals
from core import age
from services import push

logger = logging.getLogger(__name__)


def process_pending(session_factory, limit: int = 50, alert_id: int | None = None) -> dict:
    db = session_factory()
    processed = recorded = submitted = failed = 0
    suppressed = 0
    try:
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        claimable = or_(
            NotificationOutbox.status.in_(("pending", "failed")),
            and_(NotificationOutbox.status == "processing",
                 NotificationOutbox.claimed_at < now - timedelta(minutes=5)),
        )
        query = db.query(NotificationOutbox).filter(
            claimable
        ).order_by(NotificationOutbox.id.asc())
        if alert_id is not None:
            query = query.filter(NotificationOutbox.alert_id == alert_id)
        rows = query.limit(max(1, min(int(limit), 200))).all()
        for row in rows:
            claimed = db.execute(update(NotificationOutbox)
                .where(NotificationOutbox.id == row.id, claimable)
                .values(status="processing", claimed_at=now))
            db.commit()
            if claimed.rowcount != 1:
                continue
            db.refresh(row)
            processed += 1
            # 重试时授权可能已撤回，不能把之前积压的健康信息继续发给家属。
            elder = db.get(User, row.elder_id)
            receiver = db.get(User, row.receiver_id)
            binding = db.query(FamilyBinding).filter_by(
                elder_id=row.elder_id, family_id=row.receiver_id, status="active").first()
            tier = age.age_tier(elder.birth_ym) if elder else age.TIER_UNKNOWN
            allowed = bool(elder and receiver and binding and receiver.role == "family"
                           and (tier == age.TIER_SENIOR or
                                (tier == age.TIER_YOUNGER and elder.sync_summary_to_family)))
            if row.alert_id is not None:
                alert = db.get(VitalAlert, row.alert_id)
                allowed = allowed and bool(alert and alert.elder_id == row.elder_id
                                           and (alert.vital_id is None or db.get(Vitals, alert.vital_id)))
            if not allowed:
                row.status = "suppressed"
                row.last_error = "当前绑定、共享授权或来源事件已失效"
                suppressed += 1
                db.commit()
                continue
            try:
                push.send_push(row.receiver_id, row.title, row.content)
                row.retry_count += 1
                row.last_error = None
                if push.adapter_name() == "memory":
                    row.status = "recorded"
                    recorded += 1
                else:
                    row.status = "submitted"
                    submitted += 1
            except Exception as exc:
                row.retry_count += 1
                row.status = "failed"
                row.last_error = str(exc)[:500]
                failed += 1
                logger.exception("通知 outbox 发送失败 id=%s", row.id)
            db.commit()
        db.commit()
        return {"processed": processed, "recorded": recorded,
                "submitted": submitted, "failed": failed, "suppressed": suppressed}
    finally:
        db.close()


def status_for_alert(db, alert_id: int) -> str:
    rows = db.query(NotificationOutbox).filter(NotificationOutbox.alert_id == alert_id).all()
    if not rows:
        return "no_recipients"
    if all(row.status == "suppressed" for row in rows):
        return "suppressed"
    if all(row.status in ("pending", "processing") for row in rows):
        return "pending"
    if any(row.status in ("pending", "processing", "failed", "suppressed") for row in rows):
        return "failed" if all(row.status == "failed" for row in rows) else "partial"
    if all(row.status == "recorded" for row in rows):
        return "recorded"
    return "submitted"

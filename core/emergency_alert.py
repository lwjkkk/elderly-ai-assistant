"""Persist current emergency alerts for currently authorized family recipients.
Screening is shared with chat/symptom triage; no phone-delivery claim is made.
"""
from __future__ import annotations
import logging
import threading
from datetime import datetime, timedelta, timezone
from sqlalchemy import text as sql_text
from core.emergency_rules import LABELS as _EMERGENCY_LABELS, LABEL_MAP
from core.tiered_answer import _EMERGENCY_SEEK_PREFIX
from services import push as push_svc
from services.medication_notifications import family_allowed
from core.emergency_presentation import category_labels

logger = logging.getLogger(__name__)
_last_notify: dict[int, datetime] = {}  # Compatibility only; dedupe is durable.
_DEDUP_WINDOW = timedelta(minutes=5)


def detect_emergency(text: str) -> list[str]:
    from core.emergency_triage import assess
    return assess(text)['emergency_types']


def _llm_judge_emergency(text: str) -> list[str]:
    from core.emergency_triage import _bounded_judge
    status,types = _bounded_judge(text)
    return types if status=='urgent' else []


def _labels_for(keys: list[str]) -> list[str]:
    return category_labels(keys)


def notify_family_async(db_session_factory, elder_user, question: str, types: list[str]) -> threading.Thread:
    elder_id = elder_user.id
    keys = list(dict.fromkeys(t for t in types if isinstance(t,str) and t in LABEL_MAP))
    def run():
        from db.models import User, FamilyBinding, FamilyMessage, NotificationOutbox
        db = db_session_factory()
        try:
            if not keys:
                return
            if db.bind.dialect.name=='sqlite':
                db.execute(sql_text('BEGIN IMMEDIATE'))
            elder = db.get(User,elder_id)
            if elder is None or elder.role!='elder':
                return
            now = datetime.now(timezone.utc).replace(tzinfo=None)
            bindings = db.query(FamilyBinding).filter_by(elder_id=elder_id,status='active').all()
            seen = set()
            for binding in bindings:
                # Re-read current binding, birth/age policy and privacy status;
                # missing birth, revoked sharing or invalid recipient never pass.
                if (not binding.family_id or binding.family_id in seen
                        or not family_allowed(db,elder_id,binding.family_id)):
                    continue
                seen.add(binding.family_id)
                fresh = []
                for key in keys:
                    prefix = f'emergency:{key}:elder:{elder_id}:family:{binding.family_id}:'
                    recent = db.query(NotificationOutbox.id).filter(
                        NotificationOutbox.elder_id==elder_id,
                        NotificationOutbox.receiver_id==binding.family_id,
                        NotificationOutbox.dedupe_key.like(prefix+'%'),
                        NotificationOutbox.created_at>now-_DEDUP_WINDOW).first()
                    if not recent:
                        fresh.append(key)
                        db.add(NotificationOutbox(elder_id=elder_id,receiver_id=binding.family_id,
                            kind='emergency_chat',channel='in_app' if push_svc.adapter_name()=='memory' else 'push',
                            status='pending',title='紧急情况提醒',
                            content=f'提醒类别：{category_labels([key])[0]}。请立即联系老人或拨打120求助。',
                            created_at=now,
                            dedupe_key=prefix+f'bucket:{int(now.replace(tzinfo=timezone.utc).timestamp()//300)}'))
                if fresh:
                    labels = '、'.join(_labels_for(fresh))
                    db.add(FamilyMessage(binding_id=binding.id,sender_id=elder_id,kind='emergency_alert',
                        content={'type':'emergency_chat','origin':'system','elder_id':elder_id,
                                 'emergency_types':fresh,'emergency_labels':labels,'question':question[:200],
                                 'reported_question':question,
                                 'advice':'老人可能出现紧急症状，请立即联系老人或拨打120求助。',
                                 'seek_prefix':_EMERGENCY_SEEK_PREFIX}))
            db.commit()
        except Exception as exc:
            db.rollback()
            logger.warning('紧急告警记录失败 error_type=%s',type(exc).__name__)
            return
        finally:
            db.close()
        try:
            from services.notification_outbox import process_pending
            process_pending(db_session_factory)
        except Exception as exc:
            logger.warning('紧急告警已记录，派发等待重试 error_type=%s',type(exc).__name__)
    worker = threading.Thread(target=run,daemon=True)
    worker.start()
    return worker

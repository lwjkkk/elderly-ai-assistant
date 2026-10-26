"""Transactional medication notices. No transport calls before DB commit."""
from datetime import datetime, timedelta, timezone

from sqlalchemy.exc import IntegrityError

from core import age
from db.models import User, Medication, MedicationLog, FamilyBinding, FamilyMessage, NotificationOutbox
from services import push

SHANGHAI = timezone(timedelta(hours=8))
KINDS = ("medication_due", "medication_missed")


def family_allowed(db, elder_id, receiver_id):
    elder = db.get(User, elder_id)
    receiver = db.get(User, receiver_id)
    binding = db.query(FamilyBinding).filter_by(
        elder_id=elder_id, family_id=receiver_id, status="active").first()
    tier = age.age_tier(elder.birth_ym) if elder else age.TIER_UNKNOWN
    return bool(elder and receiver and receiver.role == "family" and binding and
                (tier == age.TIER_SENIOR or
                 (tier == age.TIER_YOUNGER and elder.sync_summary_to_family)))


def source_current(db, row, now):
    """Validate source/schedule on retry; never send a stale take-medication prompt."""
    if row.kind not in KINDS:
        return True
    med = db.get(Medication, row.medication_id) if row.medication_id else None
    if not med or med.elder_id != row.elder_id or row.scheduled_for is None:
        return False
    scheduled = row.scheduled_for.replace(tzinfo=timezone.utc).astimezone(SHANGHAI)
    day, slot = scheduled.strftime("%Y-%m-%d"), scheduled.strftime("%H:%M")
    if slot not in med.times or (med.start_date and day < med.start_date):
        return False
    if row.expires_at is not None and now > row.expires_at:
        return False
    log = db.query(MedicationLog).filter_by(medication_id=med.id, date=day, slot=slot).first()
    expected = "pending" if row.kind == "medication_due" else "missed"
    return bool(log and log.status == expected)


def stage(db, med, day, slot, kind, grace_minutes):
    """Unique outbox and its family card are created together, safe across workers."""
    elder = db.get(User, med.elder_id)
    if elder is None:
        return []
    due = datetime.strptime(day+" "+slot, "%Y-%m-%d %H:%M").replace(tzinfo=SHANGHAI)
    due_utc = due.astimezone(timezone.utc).replace(tzinfo=None)
    is_due = kind == "medication_due"
    title = "用药提醒" if is_due else "用药未打卡提醒"
    message = (f"已到 {med.name}（{med.dosage}）的计划时间，请按医嘱核对服药情况，避免重复服药。" if is_due else
               f"{day} {slot} 的 {med.name} 超过{grace_minutes}分钟未打卡，请联系确认；不代表实际未服药，请勿自行补服或加量。")
    recipients = [(elder.id, None)] if is_due else []
    bindings = db.query(FamilyBinding).filter_by(elder_id=elder.id, status="active").all()
    seen = {elder.id}
    for binding in bindings:
        if binding.family_id not in seen and family_allowed(db, elder.id, binding.family_id):
            recipients.append((binding.family_id, binding.id));seen.add(binding.family_id)
    ids = []
    for receiver_id, binding_id in recipients:
        key = f"{kind}:{med.id}:{day}:{slot}:{receiver_id}"
        if db.query(NotificationOutbox.id).filter_by(dedupe_key=key).first():
            continue
        try:
            with db.begin_nested():
                notice = NotificationOutbox(elder_id=elder.id, receiver_id=receiver_id,
                    kind=kind, medication_id=med.id, scheduled_for=due_utc,
                    expires_at=due_utc+timedelta(minutes=grace_minutes) if is_due else due_utc+timedelta(days=2),
                    channel="in_app" if push.adapter_name()=="memory" else "push", status="pending",
                    title=title, content=message, dedupe_key=key)
                db.add(notice);db.flush()
                if binding_id is not None:
                    db.add(FamilyMessage(binding_id=binding_id, sender_id=elder.id,
                        kind="health",
                        content={"type":kind, "origin":"system", "elder_id":elder.id,
                                 "medication_id":med.id, "date":day, "slot":slot,
                                 "title":title, "message":message, "lines":[message],
                                 "status":"pending" if is_due else "missed",
                                 "notification_id":notice.id}))
                db.flush()
                ids.append(notice.id)
        except IntegrityError:
            # Competing workers committed this same logical notice.
            if not db.query(NotificationOutbox.id).filter_by(dedupe_key=key).first():
                raise
    return ids

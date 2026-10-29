"""Presentation times: persisted naive timestamps are UTC, never server local time."""
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

BEIJING = ZoneInfo("Asia/Shanghai")


def as_beijing(value: datetime | None) -> datetime | None:
    """Preserve the instant and existing offsets; interpret SQLite naive values as UTC."""
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(BEIJING)


def beijing_isoformat(value: datetime | None) -> str | None:
    local = as_beijing(value)
    return local.isoformat() if local is not None else None

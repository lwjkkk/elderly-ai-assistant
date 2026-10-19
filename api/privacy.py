# 隐私开关接口：老人控制「对话摘要是否同步给家属」
# 权限：仅 elder 可读写自己的；family 调用返回 403（家属不能替长辈开关）

from fastapi import APIRouter, Depends, HTTPException
from datetime import datetime, timezone
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User
from db.schemas import PrivacyOut, PrivacyUpdate
from core.security import get_current_user
from core import age as age_mod

router = APIRouter(prefix="/api/privacy", tags=["隐私开关"])


def _require_elder(current: User) -> None:
    """隐私开关只允许老人本人操作。"""
    if current.role != "elder":
        raise HTTPException(status_code=403, detail="只有老人本人能设置隐私开关")


def _privacy_out(db, current: User) -> PrivacyOut:
    """读取时强制 senior 分享落库，并返回分层/强制状态。"""
    age_mod.enforce_senior_share(db, current)
    return PrivacyOut(
        sync_summary_to_family=current.sync_summary_to_family,
        age_tier=age_mod.age_tier(current.birth_ym),
        forced_share=age_mod.forced_share(current.birth_ym),
    )


@router.get("", response_model=PrivacyOut)
def get_privacy(db: Session = Depends(get_db),
                current: User = Depends(get_current_user)):
    """读取当前老人的隐私开关状态（满60周岁为强制分享）。"""
    _require_elder(current)
    return _privacy_out(db, current)


@router.put("", response_model=PrivacyOut)
def update_privacy(payload: PrivacyUpdate,
                   db: Session = Depends(get_db),
                   current: User = Depends(get_current_user)):
    """更新当前老人的隐私开关，返回最新值。

    开启隐私（sync_summary_to_family=False）：记录当前时间到 privacy_enabled_at，
        此后新产生的对话摘要/查药记录不再同步给家属；开启前的历史仍可见。
    关闭隐私（sync_summary_to_family=True）：清空 privacy_enabled_at，全部恢复同步。
    满60周岁及以上为强制分享分层：不允许关闭隐私（拒绝设为 False）。
    """
    _require_elder(current)
    if payload.sync_summary_to_family is False and age_mod.is_senior(current.birth_ym):
        raise HTTPException(status_code=403,
                            detail="满60周岁及以上为强制分享模式，隐私需分享给子女，不能关闭")
    current.sync_summary_to_family = payload.sync_summary_to_family
    if payload.sync_summary_to_family:
        current.privacy_enabled_at = None
    else:
        # 与数据库 CURRENT_TIMESTAMP 产生的 UTC 时间保持一致，避免本地时区
        # （例如 UTC+8）导致隐私开启后的记录被误认为是开启前的记录。
        current.privacy_enabled_at = datetime.now(timezone.utc).replace(tzinfo=None)
    db.commit()
    db.refresh(current)
    return _privacy_out(db, current)

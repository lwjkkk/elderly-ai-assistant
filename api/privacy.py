# 隐私开关接口：老人控制「对话摘要是否同步给家属」
# 权限：仅 elder 可读写自己的；family 调用返回 403（家属不能替长辈开关）

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User
from db.schemas import PrivacyOut, PrivacyUpdate
from core.security import get_current_user

router = APIRouter(prefix="/api/privacy", tags=["隐私开关"])


def _require_elder(current: User) -> None:
    """隐私开关只允许老人本人操作。"""
    if current.role != "elder":
        raise HTTPException(status_code=403, detail="只有老人本人能设置隐私开关")


@router.get("", response_model=PrivacyOut)
def get_privacy(current: User = Depends(get_current_user)):
    """读取当前老人的隐私开关状态。"""
    _require_elder(current)
    return PrivacyOut(sync_summary_to_family=current.sync_summary_to_family)


@router.put("", response_model=PrivacyOut)
def update_privacy(payload: PrivacyUpdate,
                   db: Session = Depends(get_db),
                   current: User = Depends(get_current_user)):
    """更新当前老人的隐私开关，返回最新值。"""
    _require_elder(current)
    current.sync_summary_to_family = payload.sync_summary_to_family
    db.commit()
    db.refresh(current)
    return PrivacyOut(sync_summary_to_family=current.sync_summary_to_family)

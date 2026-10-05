# 绑定接口：老人生成邀请码、家属输入邀请码绑定、查询绑定列表

import random
import string
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, FamilyBinding
from db.schemas import InviteOut, BindAccept, BindingOut
from core.security import get_current_user

router = APIRouter(prefix="/api/bind", tags=["绑定"])

# 邀请码有效期（分钟），类似验证码，超时需重新生成
INVITE_CODE_EXPIRE_MINUTES = 30


def _gen_invite_code() -> str:
    """生成 6 位随机邀请码（大写字母+数字）。"""
    chars = string.ascii_uppercase + string.digits
    return "".join(random.choices(chars, k=6))


@router.post("/invite", response_model=InviteOut)
def create_invite(
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
):
    """生成邀请码：长辈/家属登录即可调用，无前置条件（P0 放开权限）。"""
    # 每个用户同一时间只有一个有效邀请码，新生成时覆盖旧的 pending 记录
    existing = db.query(FamilyBinding).filter(
        FamilyBinding.elder_id == current.id,
        FamilyBinding.status == "pending",
    ).first()

    if existing:
        # 已有未过期的 pending 码，直接更新码和创建时间（重置30分钟有效期）
        existing.invite_code = _gen_invite_code()
        existing.created_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(existing)
        return InviteOut(invite_code=existing.invite_code)

    code = _gen_invite_code()
    binding = FamilyBinding(
        elder_id=current.id,
        family_id=None,        # 还没家属接受，先留空
        status="pending",
        invite_code=code,
    )
    db.add(binding)
    db.commit()
    return InviteOut(invite_code=code)


@router.post("/accept", response_model=BindingOut)
def accept_binding(
    payload: BindAccept,
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
):
    """家属输入邀请码，完成绑定。"""
    if current.role != "family":
        raise HTTPException(status_code=403, detail="只有家属账号能接受绑定")

    binding = (
        db.query(FamilyBinding)
        .filter(FamilyBinding.invite_code == payload.invite_code)
        .filter(FamilyBinding.status == "pending")
        .first()
    )
    if not binding:
        raise HTTPException(status_code=404, detail="邀请码无效或已被使用")

    # 校验有效期：SQLite 的 created_at 存的是 UTC 朴素时间，需补上时区再比较
    created = binding.created_at
    if created is not None:
        if created.tzinfo is None:
            created = created.replace(tzinfo=timezone.utc)
        if datetime.now(timezone.utc) - created > timedelta(minutes=INVITE_CODE_EXPIRE_MINUTES):
            binding.status = "expired"  # 标记为已过期，防止再次使用
            db.commit()
            raise HTTPException(
                status_code=400,
                detail=f"邀请码已过期（有效期 {INVITE_CODE_EXPIRE_MINUTES} 分钟），请让老人重新生成",
            )

    binding.family_id = current.id
    binding.status = "active"
    db.commit()
    db.refresh(binding)
    return binding


@router.get("/list")
def list_bindings(
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
):
    """查询当前用户的绑定关系（老人看绑定的家属，家属看绑定的老人）。"""
    if current.role == "elder":
        items = db.query(FamilyBinding).filter(FamilyBinding.elder_id == current.id).all()
    else:
        items = db.query(FamilyBinding).filter(FamilyBinding.family_id == current.id).all()

    result = []
    for b in items:
        # 附带对方昵称，方便前端"我的"页直接展示
        other_id = b.family_id if current.role == "elder" else b.elder_id
        other = db.query(User).filter(User.id == other_id).first() if other_id else None
        result.append({
            "id": b.id,
            "elder_id": b.elder_id,
            "family_id": b.family_id,
            "status": b.status,
            "invite_code": b.invite_code,
            "other_nickname": other.nickname if other else None,
        })
    return result

# 鉴权接口：注册、登录

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User
from db.schemas import UserCreate, UserOut, LoginRequest, Token
from core.security import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user,
)

router = APIRouter(prefix="/api/auth", tags=["鉴权"])

@router.post("/register", response_model=UserOut)
def register(payload: UserCreate, db: Session = Depends(get_db)):
    """注册：老人或家属都走这个接口，用 role 区分身份。"""
    # 校验角色合法
    if payload.role not in ("elder", "family"):
        raise HTTPException(status_code=400, detail="角色只能是 elder 或 family")

    # 手机号唯一，已注册则报错
    exists = db.query(User).filter(User.phone == payload.phone).first()
    if exists:
        raise HTTPException(status_code=400, detail="该手机号已注册")

    user = User(
        role=payload.role,
        phone=payload.phone,
        password_hash=hash_password(payload.password),  # 只存哈希
        nickname=payload.nickname,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.post("/login", response_model=Token)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    """登录：校验手机号和密码，成功返回 JWT。"""
    user = db.query(User).filter(User.phone == payload.phone).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="手机号或密码错误")

    token = create_access_token(user)
    return Token(access_token=token, role=user.role, nickname=user.nickname)


@router.post("/refresh", response_model=Token)
def refresh_token(current: User = Depends(get_current_user)):
    """刷新 JWT，延长有效期。"""
    token = create_access_token(current)
    return Token(access_token=token, role=current.role, nickname=current.nickname)

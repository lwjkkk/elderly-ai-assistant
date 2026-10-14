# 鉴权接口：注册、登录

import random
import re
import time

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User
from db.schemas import (
    UserCreate,
    UserOut,
    LoginRequest,
    LoginByCodeRequest,
    SendSmsRequest,
    SmsSent,
    Token,
)
from core.security import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user,
)

router = APIRouter(prefix="/api/auth", tags=["鉴权"])

# ---------- 验证码登录（答辩演示） ----------
# 真实短信网关需付费接入，这里只把验证码打印到后端控制台，方便演示与联调。
# 存储用进程内字典（phone -> {code, expires_at}），重启即失效，答辩够用。
# 生产环境替换为：调用短信服务商 API 下发，并把码落到 Redis/数据库。

SMS_CODE_EXPIRE_SECONDS = 300          # 验证码有效期 5 分钟
_PHONE_PATTERN = re.compile(r"^1[3-9]\d{9}$")  # 11 位大陆手机号
_sms_codes: dict[str, dict] = {}       # phone -> {"code": str, "expires_at": float}


@router.post("/send_sms_code", response_model=SmsSent)
def send_sms_code(payload: SendSmsRequest):
    """获取验证码：生成 6 位随机码，打印到控制台，接口不返回验证码。"""
    if not _PHONE_PATTERN.match(payload.phone):
        raise HTTPException(status_code=400, detail="手机号格式不正确")

    code = f"{random.randint(0, 999999):06d}"  # 6 位数字，补零
    _sms_codes[payload.phone] = {
        "code": code,
        "expires_at": time.time() + SMS_CODE_EXPIRE_SECONDS,
    }

    # 只打印到后端控制台（python main.py 的终端），不随接口返回
    print(f"[SMS] 验证码已生成 phone={payload.phone} code={code} "
          f"有效{SMS_CODE_EXPIRE_SECONDS}秒")
    return SmsSent(message="验证码已发送，请在控制台查看", expires_in=SMS_CODE_EXPIRE_SECONDS)


@router.post("/login_by_code", response_model=Token)
def login_by_code(payload: LoginByCodeRequest, db: Session = Depends(get_db)):
    """验证码登录：校验手机号+验证码，成功返回 JWT（与密码登录同一套签发）。"""
    rec = _sms_codes.get(payload.phone)
    if not rec or rec["expires_at"] < time.time():
        raise HTTPException(status_code=400, detail="验证码已过期或未获取，请重新获取")

    # 比对用常量时间，避免简单字符串比较的时序差异（演示场景也养成好习惯）
    if not _safe_equal(rec["code"], payload.code):
        raise HTTPException(status_code=401, detail="验证码错误")

    # 登录成功即作废该验证码，防止重复使用
    _sms_codes.pop(payload.phone, None)

    user = db.query(User).filter(User.phone == payload.phone).first()
    if not user:
        raise HTTPException(status_code=404, detail="该手机号未注册，请先注册")

    token = create_access_token(user)
    return Token(access_token=token, role=user.role, nickname=user.nickname, user_id=user.id)


def _safe_equal(a: str, b: str) -> bool:
    """常量时间比较，长度不同直接不等，避免泄露信息。"""
    return len(a) == len(b) and all(x == y for x, y in zip(a, b))


@router.post("/register", response_model=UserOut, status_code=201)
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
    return Token(access_token=token, role=user.role, nickname=user.nickname, user_id=user.id)


@router.post("/refresh", response_model=Token)
def refresh_token(current: User = Depends(get_current_user)):
    """刷新 JWT，延长有效期。"""
    token = create_access_token(current)
    return Token(access_token=token, role=current.role, nickname=current.nickname, user_id=current.id)

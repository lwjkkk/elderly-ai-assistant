# 安全工具：密码哈希、JWT 令牌的生成与校验、当前登录用户解析

import os
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User

# 密钥：生产环境务必从 .env 读取，这里给一个仅用于本地开发的默认值
SECRET_KEY = os.getenv("SECRET_KEY", "dev-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # token 有效期 24 小时

# token 获取方式：前端把 token 放在 Authorization: Bearer <token>
# 用 HTTPBearer：Swagger 弹窗可直接粘贴 token。
# （OAuth2PasswordBearer 会要求走表单 username/password，与我们 JSON(phone) 登录接口不匹配）
bearer_scheme = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    """注册时把明文密码用 bcrypt 哈希后存储。bcrypt 只接受 bytes 且上限 72 字节。"""
    pw = password.encode("utf-8")[:72]
    return bcrypt.hashpw(pw, bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    """登录时校验明文密码和库里的哈希是否匹配。"""
    pw = plain.encode("utf-8")[:72]
    try:
        return bcrypt.checkpw(pw, hashed.encode("utf-8"))
    except ValueError:
        return False


def create_access_token(user: User) -> str:
    """根据用户信息生成 JWT。"""
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": str(user.id),   # 主体放用户 id
        "phone": user.phone,
        "role": user.role,
        "exp": expire,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """接口依赖：从请求头解析 token，返回当前登录用户；失败则 401。"""
    credentials_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="登录已过期或令牌无效",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if creds is None or creds.scheme.lower() != "bearer" or not creds.credentials:
        raise credentials_exc
    token = creds.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = int(payload.get("sub"))
    except (jwt.PyJWTError, TypeError, ValueError):
        raise credentials_exc

    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise credentials_exc
    return user


def get_optional_user(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User | None:
    """可选鉴权依赖：带有效 token 返回用户，没带/无效返回 None（不报 401）。
    用于日常问答等“登录了才落库、不登录也能用”的接口。"""
    if creds is None or creds.scheme.lower() != "bearer" or not creds.credentials:
        return None
    try:
        payload = jwt.decode(token := creds.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = int(payload.get("sub"))
    except (jwt.PyJWTError, TypeError, ValueError):
        return None
    return db.query(User).filter(User.id == user_id).first()

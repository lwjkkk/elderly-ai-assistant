# 用户资料接口：资料编辑多端同步（昵称/性别/出生年月/头像）
# 说明：资料保存在服务端数据库，前端登录后拉取/修改，换设备不丢。
# 鉴权：Bearer token，仅本人可改自己的资料（不采用 elder_id 那套）。

import base64
import os
import re
import uuid

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User
from db.schemas import UserProfileUpdate, UserProfileOut
from core.security import get_current_user

router = APIRouter(prefix="/api/users", tags=["用户资料"])

AVATAR_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads", "avatars")
os.makedirs(AVATAR_DIR, exist_ok=True)

# 性别固定枚举：男 / 女 / 空字符串（空=未设置）
_VALID_GENDER = {"男", "女", ""}
# 出生年月固定格式：YYYY-MM
_BIRTH_YM_PATTERN = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")


@router.get("/profile", response_model=UserProfileOut)
def get_profile(db: Session = Depends(get_db),
                current: User = Depends(get_current_user)):
    """读取本人资料。"""
    return UserProfileOut.model_validate(current)


@router.put("/profile", response_model=UserProfileOut)
def update_profile(payload: UserProfileUpdate,
                   db: Session = Depends(get_db),
                   current: User = Depends(get_current_user)):
    """更新本人资料（全可选，只传改了的）。返回落库后的完整资料。"""
    user = db.query(User).filter(User.id == current.id).first()
    if not user:
        raise HTTPException(status_code=404, detail="用户不存在")

    # 昵称
    if payload.nickname is not None:
        nickname = payload.nickname.strip()
        if not nickname:
            raise HTTPException(status_code=400, detail="昵称不能为空")
        user.nickname = nickname

    # 性别：枚举校验
    if payload.gender is not None:
        if payload.gender not in _VALID_GENDER:
            raise HTTPException(status_code=400,
                                detail="性别只能是 男 / 女 / 空字符串(未设置)")
        user.gender = payload.gender if payload.gender else None

    # 出生年月：YYYY-MM 格式校验
    if payload.birth_ym is not None:
        if not _BIRTH_YM_PATTERN.match(payload.birth_ym):
            raise HTTPException(status_code=400,
                                detail="出生年月格式应为 YYYY-MM，例如 1955-08")
        user.birth_ym = payload.birth_ym

    # 头像：base64 存文件，返回相对 URL
    if payload.avatar_base64 is not None and payload.avatar_base64.strip():
        avatar_url = _save_avatar(payload.avatar_base64.strip())
        user.avatar_url = avatar_url

    db.commit()
    db.refresh(user)
    return UserProfileOut.model_validate(user)


def _save_avatar(avatar_base64: str) -> str:
    """把 base64 头像写盘（支持带 data:image/...;base64, 前缀），返回相对 URL。"""
    if avatar_base64.startswith("data:"):
        avatar_base64 = avatar_base64.split(",", 1)[1]
    try:
        data = base64.b64decode(avatar_base64)
    except Exception:
        raise HTTPException(status_code=400, detail="头像图片编码无效，请重新上传")
    if not data:
        raise HTTPException(status_code=400, detail="头像图片为空，请重新上传")
    # 限定为常见头像格式，避免异常文件；缺扩展名按 jpg
    filename = f"{uuid.uuid4().hex}.jpg"
    filepath = os.path.join(AVATAR_DIR, filename)
    with open(filepath, "wb") as f:
        f.write(data)
    return f"/api/users/avatar/{filename}"


@router.get("/avatar/{filename}")
def get_avatar(filename: str):
    """查看头像原图（无需鉴权，和体检/查药图片一致的访问方式）。"""
    filepath = os.path.join(AVATAR_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="头像不存在")
    return FileResponse(filepath)


@router.delete('/avatar')
def delete_avatar(db: Session = Depends(get_db), current: User = Depends(get_current_user)):
    user = db.query(User).filter(User.id == current.id).first()
    old_url = user.avatar_url or ''
    user.avatar_url = None
    db.commit()
    if old_url.startswith('/api/users/avatar/'):
        path = os.path.join(AVATAR_DIR, os.path.basename(old_url))
        if os.path.isfile(path):
            os.remove(path)
    return {'ok': True}

# 问诊录音接口：上传录音、按老人查询列表

import os
import uuid
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Header
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, FamilyBinding, ConsultRecord
from db.schemas import ConsultOut
from core.security import get_current_user
from core.security import SECRET_KEY, ALGORITHM
from config.settings import HOST, PORT

router = APIRouter(prefix="/api/consults", tags=["问诊录音"])

# 录音存储目录（本地），生产环境可替换为对象存储
UPLOAD_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads", "consults")
os.makedirs(UPLOAD_DIR, exist_ok=True)

# Android / Flutter 文件选择器常把按字节构造的 MultipartFile 标为
# application/octet-stream，因此以允许的扩展名确定实际音频类型。
AUDIO_TYPES = {
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".m4a": "audio/mp4",
    ".aac": "audio/aac",
    ".3gp": "audio/3gpp",
    ".ogg": "audio/ogg",
    ".opus": "audio/ogg",
    ".flac": "audio/flac",
}

_AUDIO_URL_TOKEN_TTL = timedelta(minutes=15)


def _audio_url_for_user(record: ConsultRecord, current: User) -> str:
    """Return a short-lived, file-scoped URL usable by native audio players without headers."""
    import jwt

    filename = record.audio_url.rsplit("/", 1)[-1]
    token = jwt.encode(
        {
            "sub": str(current.id),
            "scope": "consult_audio",
            "filename": filename,
            "exp": datetime.now(timezone.utc) + _AUDIO_URL_TOKEN_TTL,
        },
        SECRET_KEY,
        algorithm=ALGORITHM,
    )
    return f"{record.audio_url}?{urlencode({'token': token})}"


def resolve_elder_id(db: Session, current: User, elder_id: int | None) -> int:
    """解析目标数据归属：
    - 老人：总是操作自己的数据；
    - 家属：传 elder_id 则必须已绑定该老人；不传则操作自己的本人记录。
    """
    if current.role == "elder":
        return current.id
    if elder_id is None:
        return current.id
    binding = (
        db.query(FamilyBinding)
        .filter(FamilyBinding.elder_id == elder_id)
        .filter(FamilyBinding.family_id == current.id)
        .filter(FamilyBinding.status == "active")
        .first()
    )
    if not binding:
        raise HTTPException(status_code=403, detail="未绑定该老人，无权操作")
    return elder_id


@router.post("/upload", response_model=ConsultOut)
async def upload_consult(
    file: UploadFile = File(..., description="录音文件（mp3/wav/m4a）"),
    duration: int | None = Form(None, description="录音时长（秒）"),
    hospital: str | None = Form(None, description="医院名"),
    doctor: str | None = Form(None, description="医生名"),
    elder_id: int | None = Form(None, description="家属代上传时指定老人id"),
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
):
    """上传问诊录音，保存到本地并记录。"""
    target = resolve_elder_id(db, current, elder_id)

    # 文件名来自移动端上传，先取基本名并校验扩展名，避免路径穿越。
    original_name = (file.filename or "").replace("\\", "/").rsplit("/", 1)[-1]
    ext = os.path.splitext(original_name)[1].lower()
    media_type = AUDIO_TYPES.get(ext)
    if not media_type:
        raise HTTPException(status_code=400, detail="仅支持 mp3/wav/m4a/aac/3gp/ogg/opus/flac 音频")

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="录音文件为空，请重新选择")

    # 生成唯一文件名，使用已校验的扩展名。
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)
    with open(filepath, "wb") as f:
        f.write(content)

    # 本地路径作为 URL（前端拼接 http://host:port/api/consults/audio/xxx 访问）
    audio_url = f"/api/consults/audio/{filename}"

    record = ConsultRecord(
        elder_id=target,
        audio_url=audio_url,
        duration=duration,
        hospital=hospital,
        doctor=doctor,
    )
    try:
        db.add(record)
        db.commit()
        db.refresh(record)
    except Exception:
        db.rollback()
        if os.path.exists(filepath):
            os.remove(filepath)
        raise
    out = ConsultOut.model_validate(record).model_dump()
    out["audio_url"] = _audio_url_for_user(record, current)
    return out


@router.get("", response_model=list[ConsultOut])
def list_consults(elder_id: int | None = None,
                  db: Session = Depends(get_db),
                  current: User = Depends(get_current_user)):
    """查询问诊录音列表。

    - 老人：返回自己的录音；
    - 家属：传 elder_id 则查指定老人；不传则返回自己的录音 + 所有已绑定老人的录音。
    """
    if current.role == "elder":
        targets = [current.id]
    elif elder_id is not None:
        # 显式指定老人：校验绑定
        binding = (
            db.query(FamilyBinding)
            .filter(FamilyBinding.elder_id == elder_id)
            .filter(FamilyBinding.family_id == current.id)
            .filter(FamilyBinding.status == "active")
            .first()
        )
        if not binding:
            raise HTTPException(status_code=403, detail="未绑定该老人，无权查看")
        targets = [elder_id]
    else:
        # 家属不传 elder_id：自己的录音 + 所有绑定老人的录音
        targets = [current.id]
        bindings = (
            db.query(FamilyBinding)
            .filter(FamilyBinding.family_id == current.id)
            .filter(FamilyBinding.status == "active")
            .all()
        )
        targets += [b.elder_id for b in bindings]

    records = (
        db.query(ConsultRecord)
        .filter(ConsultRecord.elder_id.in_(targets))
        .order_by(ConsultRecord.created_at.desc())
        .all()
    )
    result = []
    for record in records:
        out = ConsultOut.model_validate(record).model_dump()
        out["audio_url"] = _audio_url_for_user(record, current)
        result.append(out)
    return result


@router.get("/audio/{filename}")
def get_audio(filename: str,
              token: str | None = None,
              authorization: str | None = Header(None, alias="Authorization"),
              db: Session = Depends(get_db)):
    """播放/下载录音文件。

    鉴权方式二选一：
    - Authorization: Bearer <token>（普通 API 请求）
    - URL 参数 ?token=<token>（<audio> 标签播放时，浏览器不会带 header）

    允许：
    - 录音所有者本人（不管是老人还是家属自己上传的）；
    - 与录音所属老人存在有效绑定的家属。
    """
    from fastapi.responses import FileResponse
    import jwt
    from core.security import SECRET_KEY, ALGORITHM

    # 解析 token：优先 header，其次 query 参数
    raw_token = None
    if authorization and authorization.lower().startswith("bearer "):
        raw_token = authorization[7:]
    elif token:
        raw_token = token

    if not raw_token:
        raise HTTPException(status_code=401, detail="未登录")

    try:
        payload = jwt.decode(raw_token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = int(payload.get("sub"))
    except (jwt.PyJWTError, TypeError, ValueError):
        raise HTTPException(status_code=401, detail="登录已过期")

    # API 返回给音频播放器的短期令牌仅允许访问它绑定的文件。
    if payload.get("scope") == "consult_audio" and payload.get("filename") != filename:
        raise HTTPException(status_code=403, detail="该播放链接无权访问此录音")

    current = db.query(User).filter(User.id == user_id).first()
    if not current:
        raise HTTPException(status_code=401, detail="用户不存在")

    audio_url = f"/api/consults/audio/{filename}"
    record = db.query(ConsultRecord).filter(ConsultRecord.audio_url == audio_url).first()
    if not record:
        raise HTTPException(status_code=404, detail="录音文件不存在")

    # 权限校验
    if record.elder_id == current.id:
        pass  # 本人录音
    elif current.role == "family":
        binding = (
            db.query(FamilyBinding)
            .filter(FamilyBinding.elder_id == record.elder_id)
            .filter(FamilyBinding.family_id == current.id)
            .filter(FamilyBinding.status == "active")
            .first()
        )
        if not binding:
            raise HTTPException(status_code=403, detail="无权播放该录音")
    else:
        raise HTTPException(status_code=403, detail="无权播放该录音")

    filepath = os.path.join(UPLOAD_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="录音文件不存在")
    ext = os.path.splitext(filename)[1].lower()
    return FileResponse(filepath, media_type=AUDIO_TYPES.get(ext, "application/octet-stream"))

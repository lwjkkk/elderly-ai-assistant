# 问诊录音接口：上传录音、按老人查询列表

import os
import uuid

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, FamilyBinding, ConsultRecord
from db.schemas import ConsultOut
from core.security import get_current_user
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
    return record


@router.get("", response_model=list[ConsultOut])
def list_consults(elder_id: int | None = None,
                  db: Session = Depends(get_db),
                  current: User = Depends(get_current_user)):
    """查询问诊录音列表。"""
    target = resolve_elder_id(db, current, elder_id)
    return (
        db.query(ConsultRecord)
        .filter(ConsultRecord.elder_id == target)
        .order_by(ConsultRecord.created_at.desc())
        .all()
    )


@router.get("/audio/{filename}")
def get_audio(filename: str):
    """播放/下载录音文件。"""
    from fastapi.responses import FileResponse

    filepath = os.path.join(UPLOAD_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="录音文件不存在")
    ext = os.path.splitext(filename)[1].lower()
    return FileResponse(filepath, media_type=AUDIO_TYPES.get(ext, "application/octet-stream"))

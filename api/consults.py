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


def resolve_elder_id(db: Session, current: User, elder_id: int | None) -> int:
    """解析目标老人。"""
    if current.role == "elder":
        return current.id
    if elder_id is None:
        raise HTTPException(status_code=400, detail="家属操作需指定 elder_id")
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
    # 校验文件类型
    allowed = {"audio/mpeg", "audio/wav", "audio/mp4", "audio/x-m4a", "audio/aac"}
    if file.content_type not in allowed:
        raise HTTPException(status_code=400, detail=f"不支持的音频格式：{file.content_type}")

    target = resolve_elder_id(db, current, elder_id)

    # 生成唯一文件名，避免冲突
    ext = os.path.splitext(file.filename)[1] or ".mp3"
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)

    with open(filepath, "wb") as f:
        content = await file.read()
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
    db.add(record)
    db.commit()
    db.refresh(record)
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
    return FileResponse(filepath, media_type="audio/mpeg")

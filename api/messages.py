# 家人消息路由：老人/家属双端互发文字或健康消息，持久化存库

import base64
import logging
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, FamilyBinding, FamilyMessage
from core.security import get_current_user
from core import age as age_mod

router = APIRouter(prefix="/api/messages", tags=["家人消息"])
logger = logging.getLogger(__name__)
MEDIA_DIR = Path(__file__).resolve().parent.parent / 'uploads' / 'family_messages'
AUDIO_TYPES = {'.m4a': 'audio/mp4', '.wav': 'audio/wav', '.mp3': 'audio/mpeg',
               '.aac': 'audio/aac', '.ogg': 'audio/ogg', '.webm': 'audio/webm'}


def _out(message: FamilyMessage) -> dict:
    # Earlier medication notices used the symptom-emergency kind. Old clients
    # replace that kind's text with symptom/120 templates; medication check-in
    # absence is not proof of a medical emergency. Normalize only our own type.
    kind = message.kind
    content = message.content or {}
    if (kind == 'emergency_alert' and content.get('origin') == 'system'
            and content.get('type') == 'medication_missed'):
        kind = 'health'
    return {'id': message.id, 'binding_id': message.binding_id,
            'sender_id': message.sender_id, 'kind': kind,
            'content': message.content,
            'created_at': message.created_at.isoformat() if message.created_at else None}


def _message(db: Session, binding_id: int, message_id: int, current: User) -> FamilyMessage:
    binding = _assert_binding_member(db, binding_id, current)
    message = db.query(FamilyMessage).filter(
        FamilyMessage.id == message_id, FamilyMessage.binding_id == binding_id).first()
    if not message:
        raise HTTPException(status_code=404, detail='消息不存在')
    _assert_system_health_visible(db, binding, message, current)
    return message


class MessageCreate(BaseModel):
    kind: str          # text | health
    content: dict      # 结构化内容


def _assert_binding_member(db: Session, binding_id: int, current: User) -> FamilyBinding:
    """校验当前用户属于该条有效绑定；否则 403。"""
    binding = (
        db.query(FamilyBinding)
        .filter(FamilyBinding.id == binding_id)
        .filter(FamilyBinding.status == "active")
        .first()
    )
    if not binding:
        raise HTTPException(status_code=404, detail="绑定不存在或已失效")
    if current.id not in (binding.elder_id, binding.family_id):
        raise HTTPException(status_code=403, detail="无权访问该会话")
    return binding


def _is_system_health_message(message: FamilyMessage) -> bool:
    content = message.content or {}
    return (message.kind in ("health", "emergency_alert") and
            (content.get("origin") == "system" or content.get("type") in
             ("vital_alert", "emergency_chat", "emergency_alert")))


def _assert_system_health_visible(db: Session, binding: FamilyBinding,
                                  message: FamilyMessage, current: User) -> None:
    """Recheck sharing when opening a previously persisted system health alert."""
    if current.role != "family" or not _is_system_health_message(message):
        return
    elder = db.query(User).filter(User.id == binding.elder_id).first()
    allowed, reason = age_mod.family_access_guard(db, current, elder)
    if not allowed:
        detail = {
            "birth_missing": "老人资料不完整，暂不可访问系统健康消息",
            "privacy_off": "老人未开启健康资料分享，暂不可访问系统健康消息",
        }.get(reason, "无权访问该系统健康消息")
        raise HTTPException(status_code=403, detail=detail)


@router.get("/{binding_id}")
def list_messages(binding_id: int,
                  db: Session = Depends(get_db),
                  current: User = Depends(get_current_user)):
    """获取该绑定双方的历史消息，按创建顺序排列。"""
    binding = _assert_binding_member(db, binding_id, current)
    msgs = (
        db.query(FamilyMessage)
        .filter(FamilyMessage.binding_id == binding_id)
        .order_by(FamilyMessage.created_at.asc(), FamilyMessage.id.asc())
        .all()
    )
    visible = []
    for m in msgs:
        try:
            _assert_system_health_visible(db, binding, m, current)
        except HTTPException as exc:
            if exc.status_code == 403:
                continue
            raise
        visible.append(m)
    return [_out(m) for m in visible]


@router.post("/{binding_id}")
def send_message(binding_id: int,
                 payload: MessageCreate,
                 db: Session = Depends(get_db),
                 current: User = Depends(get_current_user)):
    """发送一条消息到该绑定会话。"""
    binding = _assert_binding_member(db, binding_id, current)
    if payload.kind not in ("text", "health", "image"):
        raise HTTPException(status_code=400, detail="消息类型不支持，语音请使用录音上传接口")
    if payload.kind == 'image':
        try:
            image = base64.b64decode(payload.content.get('image', ''), validate=True)
        except (ValueError, TypeError):
            raise HTTPException(status_code=400, detail='图片内容无效')
        if not image or len(image) > 5 * 1024 * 1024:
            raise HTTPException(status_code=400, detail='图片为空或超过5MB，请压缩后重试')
    client_id = payload.content.get('client_id')
    if client_id:
        for existing in db.query(FamilyMessage).filter(
                FamilyMessage.binding_id == binding_id,
                FamilyMessage.sender_id == current.id).all():
            if existing.content.get('client_id') == client_id:
                return _out(existing)
    msg = FamilyMessage(
        binding_id=binding_id,
        sender_id=current.id,
        kind=payload.kind,
        content=payload.content,
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return {
        "id": msg.id,
        "binding_id": msg.binding_id,
        "sender_id": msg.sender_id,
        "kind": msg.kind,
        "content": msg.content,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
    }


@router.post('/{binding_id}/audio')
async def upload_audio(binding_id: int, file: UploadFile = File(...),
                       duration: int = Form(..., ge=1, le=60), client_id: str = Form(''),
                       db: Session = Depends(get_db), current: User = Depends(get_current_user)):
    _assert_binding_member(db, binding_id, current)
    if client_id:
        for existing in db.query(FamilyMessage).filter(
                FamilyMessage.binding_id == binding_id,
                FamilyMessage.sender_id == current.id).all():
            if existing.content.get('client_id') == client_id:
                return _out(existing)
    extension = Path(file.filename or '').suffix.lower()
    if extension not in AUDIO_TYPES:
        raise HTTPException(status_code=400, detail='不支持的录音格式')
    data = await file.read(10 * 1024 * 1024 + 1)
    if not data or len(data) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail='录音为空或超过10MB')
    MEDIA_DIR.mkdir(parents=True, exist_ok=True)
    path = MEDIA_DIR / f'{uuid.uuid4().hex}{extension}'
    path.write_bytes(data)
    url = f'/api/messages/audio/{path.name}'
    message = FamilyMessage(binding_id=binding_id, sender_id=current.id, kind='audio',
        content={'kind': 'audio', 'text': url, 'dur': duration, 'client_id': client_id})
    try:
        db.add(message)
        db.commit()
        db.refresh(message)
    except Exception:
        db.rollback()
        path.unlink(missing_ok=True)
        raise
    return _out(message)


@router.get('/audio/{filename}')
def audio_file(filename: str, db: Session = Depends(get_db),
               current: User = Depends(get_current_user)):
    if Path(filename).name != filename or Path(filename).suffix.lower() not in AUDIO_TYPES:
        raise HTTPException(status_code=404, detail='录音不存在')
    url = f'/api/messages/audio/{filename}'
    message = db.query(FamilyMessage).filter(
        FamilyMessage.kind == 'audio', FamilyMessage.content['text'].as_string() == url).first()
    if not message:
        raise HTTPException(status_code=404, detail='录音不存在')
    _assert_binding_member(db, message.binding_id, current)
    path = MEDIA_DIR / filename
    if not path.is_file():
        raise HTTPException(status_code=404, detail='录音文件不存在')
    return FileResponse(path, media_type=AUDIO_TYPES[path.suffix])


@router.post('/{binding_id}/{message_id}/transcribe')
def transcribe_message(binding_id: int, message_id: int,
                       db: Session = Depends(get_db), current: User = Depends(get_current_user)):
    message = _message(db, binding_id, message_id, current)
    if message.kind != 'audio':
        raise HTTPException(status_code=400, detail='只能转写语音消息')
    content = dict(message.content)
    if content.get('transcript'):
        return {'text': content['transcript']}
    path = MEDIA_DIR / Path(content.get('text', '')).name
    if not path.is_file() or path.suffix not in AUDIO_TYPES:
        raise HTTPException(status_code=404, detail='录音文件不存在')
    try:
        from core.speech_transcription import transcribe_audio
        text = transcribe_audio(path, AUDIO_TYPES[path.suffix])
    except Exception:
        logger.exception('家人语音转写失败，message_id=%s', message_id)
        raise HTTPException(status_code=503, detail='语音转文字暂不可用，请稍后重试；录音仍可播放')
    db.refresh(message)
    content = dict(message.content)
    content['transcript'] = text
    message.content = content
    db.commit()
    return {'text': text}


@router.delete('/{binding_id}/{message_id}')
def delete_message(binding_id: int, message_id: int,
                   db: Session = Depends(get_db), current: User = Depends(get_current_user)):
    message = _message(db, binding_id, message_id, current)
    if message.sender_id != current.id:
        raise HTTPException(status_code=403, detail='只能删除自己发送的消息')
    path = MEDIA_DIR / Path(message.content.get('text', '')).name if message.kind == 'audio' else None
    db.delete(message)
    db.commit()
    if path and path.is_file():
        path.unlink()
    return {'ok': True}

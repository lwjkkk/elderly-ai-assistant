# 家人消息路由：老人/家属双端互发文字或健康消息，持久化存库

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, FamilyBinding, FamilyMessage
from core.security import get_current_user

router = APIRouter(prefix="/api/messages", tags=["家人消息"])


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


@router.get("/{binding_id}")
def list_messages(binding_id: int,
                  db: Session = Depends(get_db),
                  current: User = Depends(get_current_user)):
    """获取该绑定双方的历史消息，按创建顺序排列。"""
    _assert_binding_member(db, binding_id, current)
    msgs = (
        db.query(FamilyMessage)
        .filter(FamilyMessage.binding_id == binding_id)
        .order_by(FamilyMessage.created_at.asc(), FamilyMessage.id.asc())
        .all()
    )
    return [
        {
            "id": m.id,
            "binding_id": m.binding_id,
            "sender_id": m.sender_id,
            "kind": m.kind,
            "content": m.content,
            "created_at": m.created_at.isoformat() if m.created_at else None,
        }
        for m in msgs
    ]


@router.post("/{binding_id}")
def send_message(binding_id: int,
                 payload: MessageCreate,
                 db: Session = Depends(get_db),
                 current: User = Depends(get_current_user)):
    """发送一条消息到该绑定会话。"""
    binding = _assert_binding_member(db, binding_id, current)
    if payload.kind not in ("text", "health"):
        raise HTTPException(status_code=400, detail="kind 只能是 text 或 health")
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

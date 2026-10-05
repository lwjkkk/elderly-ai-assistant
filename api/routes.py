# 日常问答路由 + 对话摘要读取

import threading
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from core.agent import get_agent_answer
from core.chat_summary import save_summary_sync
from core.security import get_current_user, get_optional_user
from db.database import get_db
from db.models import User, ChatSummary
from db.schemas import ChatSummaryOut
from api.meds import resolve_elder_id

router = APIRouter()


class ChatRequest(BaseModel):
    question: str


@router.post("/api/chat")
def chat(request: ChatRequest,
         db: Session = Depends(get_db),
         current: User | None = Depends(get_optional_user)):
    """日常问答。老人登录时，对属于 drug/med/selfcheck/consult 的问答后台提炼摘要落库。
    未登录也能用（可选鉴权），此时不落库。"""
    result = get_agent_answer(request.question)

    # 仅老人登录且问题属于需同步的 4 类时，异步落库（不阻塞回答返回）
    if current is not None and current.role == "elder":
        module = result.get("module", "")
        threading.Thread(
            target=save_summary_sync,
            args=(current.id, request.question, result.get("answer", ""), module),
            daemon=True,
        ).start()

    return result


@router.get("/api/chat/summaries", response_model=list[ChatSummaryOut])
def list_summaries(elder_id: int | None = None,
                   category: str | None = None,
                   limit: int = 20,
                   since: str | None = None,
                   db: Session = Depends(get_db),
                   current: User = Depends(get_current_user)):
    """对话摘要列表：老人看自己；家属传 elder_id 看绑定老人（需登录）。
    支持按 category 过滤、limit 条数、since 增量（按 created_at）。"""
    target = resolve_elder_id(db, current, elder_id)

    q = db.query(ChatSummary).filter(ChatSummary.elder_id == target)
    if category:
        q = q.filter(ChatSummary.category == category)
    if since:
        try:
            dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
            if dt.tzinfo is not None:
                dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
            q = q.filter(ChatSummary.created_at >= dt)
        except ValueError:
            pass

    q = q.order_by(ChatSummary.created_at.desc(), ChatSummary.id.desc()).limit(limit)
    return [ChatSummaryOut.model_validate(s) for s in q.all()]

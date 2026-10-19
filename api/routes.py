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
    if (current is not None and current.role == "elder"
            and current.sync_summary_to_family):
        module = result.get("module", "")
        threading.Thread(
            target=save_summary_sync,
            args=(current.id, request.question, result.get("answer", ""), module),
            daemon=True,
        ).start()

    return result


class TieredRequest(BaseModel):
    question: str


@router.post("/api/chat/tiered")
def chat_tiered(request: TieredRequest,
                db: Session = Depends(get_db),
                current: User | None = Depends(get_optional_user)):
    """健康回答三段式：老人简版/家属详版双角色输出。

    - 老人或无登录：返回老人简版（结论/建议一句要点 + 就医兜底）。
    - 家属：返回家属详版（三段完整原文 + 关注点提示）。
    输出含 source：llm=LLM 结构化生成；deterministic=LLM 失败时的确定性降级。
    """
    result = get_agent_answer(request.question)
    from core.tiered_answer import build
    role = current.role if current and current.role in ("elder", "family") else "elder"
    tiered = build(request.question, result.get("answer", ""), role)
    return {
        "module": result.get("module", ""),
        "sources": result.get("sources", []),
        "role": role,
        "source": tiered["source"],
        "parts": tiered["parts"],
        "view": tiered["view"],
    }


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

    # 家属看老人数据时：若老人开启了隐私，只返回开启时间之前的记录
    if current.role == "family" and target != current.id:
        elder = db.query(User).filter(User.id == target).first()
        if elder and not elder.sync_summary_to_family:
            if elder.privacy_enabled_at:
                q = q.filter(ChatSummary.created_at <= elder.privacy_enabled_at)
            else:
                # 兼容旧数据：开关已关闭同步但尚无开启时间时，优先保护隐私。
                q = q.filter(ChatSummary.id == -1)

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

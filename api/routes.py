# 日常问答路由 + 对话摘要读取

import threading
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session, sessionmaker

from core.agent import get_agent_answer
from core.evidence import attach_evidence
from core.chat_summary import save_summary_sync
from core.security import get_current_user, get_optional_user
from db.database import get_db
from db.models import User, ChatSummary
from db.schemas import ChatSummaryOut
from api.meds import resolve_elder_id

router = APIRouter()


def _run_chat_side_effects(question: str, result: dict, current: User | None, db: Session) -> list[str]:
    """共享普通问答与三段式接口的摘要和紧急事件副作用，单次请求只调用一次。"""
    emergency_types: list[str] = list(result.get('emergency_types') or [])
    factory = sessionmaker(bind=db.get_bind())
    if current is not None and current.role == "elder":
        from core.emergency_alert import detect_emergency, notify_family_async
        if 'emergency_types' not in result:
            emergency_types = detect_emergency(question)
        if emergency_types:
            notify_family_async(factory, current, question, emergency_types)

    from core.age import is_senior
    if (current is not None and current.role == "elder"
            and (current.sync_summary_to_family or is_senior(current.birth_ym))):
        module = result.get("module", "")
        threading.Thread(
            target=save_summary_sync,
            args=(current.id, question, result.get("answer", ""), module),
            kwargs={"session_factory": factory},
            daemon=True,
        ).start()
    return emergency_types


class ChatRequest(BaseModel):
    question: str


@router.post("/api/chat")
def chat(request: ChatRequest,
         db: Session = Depends(get_db),
         current: User | None = Depends(get_optional_user)):
    """日常问答。老人登录时，对属于 drug/med/selfcheck/consult 的问答后台提炼摘要落库。
    未登录也能用（可选鉴权），此时不落库。
    10.20 起：老人提问命中红旗紧急症状时，后台异步给授权家属发紧急告警。"""
    result = attach_evidence(get_agent_answer(request.question))

    emergency_types = _run_chat_side_effects(request.question, result, current, db)
    result["emergency"] = bool(emergency_types)
    result["emergency_types"] = emergency_types
    return result


class TieredRequest(BaseModel):
    question: str


@router.post("/api/chat/tiered")
def chat_tiered(request: TieredRequest,
                db: Session = Depends(get_db),
                current: User | None = Depends(get_optional_user)):
    """同一份回答同时返回关注点/解释/下一步/就医提醒及老人、家属双视图。

    ``view`` 根据当前角色选默认视图，双视图都来自同一次结构化生成。
    输出含 source：llm=LLM 结构化生成；deterministic=LLM 失败时的确定性降级。
    10.20 起：老人提问命中红旗紧急症状时，后台异步给授权家属发紧急告警，
    响应里带 emergency=true 供老人端显示红色横幅。
    """
    result = attach_evidence(get_agent_answer(request.question, structured_health=True))
    from core.tiered_answer import build
    role = current.role if current and current.role in ("elder", "family") else "elder"
    tiered = build(request.question, result.get("answer", ""), role, generated=True,
                   module=result.get('module', 'daily_life'))
    if result.get('answer_origin') == 'safety_rule':
        tiered['source'] = 'deterministic'

    emergency_types = _run_chat_side_effects(request.question, result, current, db)

    return {
        "schema_version": tiered["schema_version"],
        "answer": tiered["view"]["text"],
        "module": result.get("module", ""),
        "steps": [],
        "disclaimer": tiered["display_notice"],
        "sources": result.get("sources", []),
        "has_evidence": result["has_evidence"],
        "knowledge_base_hit": result["knowledge_base_hit"],
        "evidence_card": result["evidence_card"],
        "answer_footer": result["answer_footer"],
        "evidence_status": result.get("evidence_status", "none"),
        "retrieval_channel": result.get("retrieval_channel", "none"),
        "fallback_reason": result.get("fallback_reason"),
        "index_version": result.get("index_version"),
        "evidence_notice": "",
        "answer_origin": result.get('answer_origin', 'llm'),
        "safety_flags": result.get('safety_flags', []),
        "role": role,
        "source": tiered["source"],
        "parts": tiered["parts"],
        "elder_view": tiered["elder_view"],
        "family_view": tiered["family_view"],
        "view": tiered["view"],
        "elder_answer": tiered["elder_answer"],
        "family_answer": tiered["family_answer"],
        "views_distinct": tiered["views_distinct"],
        "render_mode": tiered["render_mode"],
        "display_notice": tiered["display_notice"],
        "emergency": bool(emergency_types),
        "emergency_types": emergency_types,
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

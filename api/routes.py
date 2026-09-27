# API 路由

from fastapi import APIRouter
from pydantic import BaseModel
from core.agent import get_agent_answer

router = APIRouter()

class ChatRequest(BaseModel):
    question: str
    image_base64: str = None

@router.post("/api/chat")
def chat(request: ChatRequest):
    result = get_agent_answer(request.question, request.image_base64)
    return result

# 拍照查药接口：药盒照片 OCR + LLM 大白话解读（作用/禁忌/副作用），不做诊疗

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User
from db.schemas import DrugQuery, DrugNameQuery, DrugResult
from core.security import get_current_user
from core.ocr import recognize_image
from core.qwen_llm import call_qwen
from core.disclaimer import DRUG_DISCLAIMER

router = APIRouter(prefix="/api/drugs", tags=["查药"])

# 药品科普提示词：限定只做说明书科普，严禁诊断/处方/调药
DRUG_SYSTEM_PROMPT = (
    "你是面向老年人的药品科普助手。请根据药盒上识别到的文字，用大白话分三部分说明："
    "一、这个药主要是做什么的（作用）；"
    "二、使用时要注意什么、哪些情况或人群需要特别小心（禁忌）；"
    "三、可能出现哪些不适（副作用）。"
    "要求：语言通俗、句子简短、不制造恐慌；识别信息不足就如实说明看不懂；"
    "严禁给出疾病诊断、处方、具体剂量调整、停药或换药建议，并提醒以医嘱和说明书为准。"
)


@router.post("/query", response_model=DrugResult)
def query_drug(payload: DrugQuery,
               db: Session = Depends(get_db),
               current: User = Depends(get_current_user)):
    """拍照上传药盒，返回识别文字与大白话解读。"""
    try:
        ocr_text = recognize_image(payload.image_base64)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception:
        raise HTTPException(status_code=400, detail="图片识别失败，请重新拍摄清晰的药盒照片再试")

    user_msg = f"药盒上识别到的文字如下，请用大白话解释：\n{ocr_text}"
    explanation = call_qwen(DRUG_SYSTEM_PROMPT, user_msg)

    return DrugResult(
        ocr_text=ocr_text,
        explanation=explanation,
        disclaimer=DRUG_DISCLAIMER,
    )


@router.post("/query-name", response_model=DrugResult)
def query_drug_by_name(payload: DrugNameQuery,
                       db: Session = Depends(get_db),
                       current: User = Depends(get_current_user)):
    """输入药名查药品常识，返回大白话解读。"""
    user_msg = f"请介绍药品「{payload.name}」的常识，包括作用、禁忌和副作用。"
    explanation = call_qwen(DRUG_SYSTEM_PROMPT, user_msg)

    return DrugResult(
        ocr_text=f"药品名：{payload.name}",
        explanation=explanation,
        disclaimer=DRUG_DISCLAIMER,
    )

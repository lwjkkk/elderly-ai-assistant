# 拍照查药接口：药盒照片 OCR + LLM 大白话解读（作用/禁忌/副作用），不做诊疗

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, DrugQuery
from db.schemas import (
    DrugQuery as DrugQuerySchema, DrugNameQuery, DrugResult, DrugQueryOut,
)
from core.security import get_current_user
from core.ocr import recognize_image
from core.qwen_llm import call_qwen
from core.disclaimer import DRUG_DISCLAIMER
from api.meds import resolve_elder_id

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


def _resolve_elder_for_drug(db: Session, current: User, elder_id: int | None) -> int:
    """查药记录归属：老人查自己；家属代查需绑定并指定 elder_id。"""
    return resolve_elder_id(db, current, elder_id)


def _save_drug_query(db: Session, elder_id: int, kind: str,
                     input_text: str | None, ocr_text: str | None,
                     explanation: str) -> None:
    """把一次查药写入 drug_queries 表，供家属端查看。"""
    db.add(DrugQuery(
        elder_id=elder_id,
        kind=kind,
        input_text=input_text,
        ocr_text=ocr_text,
        explanation=explanation,
        disclaimer=DRUG_DISCLAIMER,
    ))
    db.commit()


@router.post("/query", response_model=DrugResult)
def query_drug(payload: DrugQuerySchema,
               elder_id: int | None = None,
               db: Session = Depends(get_db),
               current: User = Depends(get_current_user)):
    """拍照上传药盒，返回识别文字与大白话解读，并落库查药记录。"""
    target = _resolve_elder_for_drug(db, current, elder_id)
    try:
        ocr_text = recognize_image(payload.image_base64)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception:
        raise HTTPException(status_code=400, detail="图片识别失败，请重新拍摄清晰的药盒照片再试")

    user_msg = f"药盒上识别到的文字如下，请用大白话解释：\n{ocr_text}"
    explanation = call_qwen(DRUG_SYSTEM_PROMPT, user_msg)

    _save_drug_query(db, target, "image", ocr_text, ocr_text, explanation)

    return DrugResult(
        ocr_text=ocr_text,
        explanation=explanation,
        disclaimer=DRUG_DISCLAIMER,
    )


@router.post("/query-name", response_model=DrugResult)
def query_drug_by_name(payload: DrugNameQuery,
                       elder_id: int | None = None,
                       db: Session = Depends(get_db),
                       current: User = Depends(get_current_user)):
    """输入药名查药品常识，返回大白话解读，并落库查药记录。"""
    target = _resolve_elder_for_drug(db, current, elder_id)
    user_msg = f"请介绍药品「{payload.name}」的常识，包括作用、禁忌和副作用。"
    explanation = call_qwen(DRUG_SYSTEM_PROMPT, user_msg)

    _save_drug_query(db, target, "name", payload.name, f"药品名：{payload.name}", explanation)

    return DrugResult(
        ocr_text=f"药品名：{payload.name}",
        explanation=explanation,
        disclaimer=DRUG_DISCLAIMER,
    )


@router.get("/records", response_model=list[DrugQueryOut])
def list_drug_records(elder_id: int | None = None,
                      limit: int = 20,
                      since: str | None = None,
                      db: Session = Depends(get_db),
                      current: User = Depends(get_current_user)):
    """查药记录列表：老人看自己；家属传 elder_id 看绑定老人。
    explanation 截断到 500 字内，家属端只做摘要展示。"""
    target = resolve_elder_id(db, current, elder_id)

    q = db.query(DrugQuery).filter(DrugQuery.elder_id == target)
    if since:
        try:
            dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
            if dt.tzinfo is not None:
                dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
            q = q.filter(DrugQuery.created_at >= dt)
        except ValueError:
            pass

    q = q.order_by(DrugQuery.created_at.desc(), DrugQuery.id.desc()).limit(limit)
    result = []
    for rec in q.all():
        d = DrugQueryOut.model_validate(rec).model_dump()
        if d.get("explanation") and len(d["explanation"]) > 500:
            d["explanation"] = d["explanation"][:500] + "……"
        result.append(d)
    return result

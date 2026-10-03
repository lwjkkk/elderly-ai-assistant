# 症状自查接口：输入症状 -> AI 建议 + 风险分级（绿黄红），家属可代提交、查看

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, SymptomCheck
from db.schemas import SymptomCreate, SymptomOut
from core.security import get_current_user
from core.health_llm import symptom_advice
from api.meds import resolve_elder_id

router = APIRouter(prefix="/api", tags=["症状自查"])


@router.post("/symptom-check", response_model=SymptomOut)
def check_symptom(payload: SymptomCreate,
                  db: Session = Depends(get_db),
                  current: User = Depends(get_current_user)):
    """提交症状描述，返回建议与风险等级，并保存记录。"""
    if not payload.input_text.strip():
        raise HTTPException(status_code=400, detail="请先描述症状")

    elder_id = resolve_elder_id(db, current, payload.elder_id)
    advice, risk = symptom_advice(payload.input_text)

    rec = SymptomCheck(
        elder_id=elder_id,
        input_text=payload.input_text,
        advice_text=advice,
        risk=risk,
    )
    db.add(rec)
    db.commit()
    db.refresh(rec)
    return rec


@router.get("/symptom-check", response_model=list[SymptomOut])
def list_symptoms(elder_id: int | None = None,
                  db: Session = Depends(get_db),
                  current: User = Depends(get_current_user)):
    """查询症状自查历史。"""
    target = resolve_elder_id(db, current, elder_id)
    return (
        db.query(SymptomCheck)
        .filter(SymptomCheck.elder_id == target)
        .order_by(SymptomCheck.created_at.desc())
        .all()
    )

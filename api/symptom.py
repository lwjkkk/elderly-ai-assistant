# 症状自查接口：输入症状 -> AI 建议 + 风险分级（绿黄红），家属可代提交、查看
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, sessionmaker

from db.database import get_db
from db.models import User, SymptomCheck
from db.schemas import SymptomCreate, SymptomOut
from core.security import get_current_user
from core.health_llm import symptom_assessment
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
    result = symptom_assessment(payload.input_text)

    rec = SymptomCheck(
        elder_id=elder_id,
        input_text=payload.input_text,
        advice_text=result['advice_text'],
        risk=result['risk'],
        answer_data={key: value for key, value in result.items()
                     if key not in ('advice_text', 'risk')},
    )
    db.add(rec)
    db.commit()
    db.refresh(rec)
    if result.get('emergency_types'):
        from db.models import FamilyBinding
        from services.medication_notifications import family_allowed
        # Explicitly preserve current active binding, birth/age sharing policy,
        # and recipient-role checks. The worker rechecks these before writing.
        bindings = db.query(FamilyBinding).filter_by(elder_id=elder_id,status='active').all()
        eligible = any(b.family_id and family_allowed(db,elder_id,b.family_id) for b in bindings)
        target = db.get(User,elder_id)
        if eligible and target is not None and target.role=='elder':
            from core.emergency_alert import notify_family_async
            notify_family_async(sessionmaker(bind=db.get_bind()),target,payload.input_text,
                                result['emergency_types'])
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

"""用药录入的说明书识别：只返回表单草稿，不产生查药或提醒记录。"""
import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.meds import resolve_elder_id
from core.ocr import OcrUnavailableError, recognize_image
from core.security import get_current_user
from db.database import get_db
from db.models import User

router = APIRouter(prefix="/api/meds", tags=["用药"])


class InstructionsImage(BaseModel):
    image_base64: str


@router.post("/recognize-instructions")
def recognize_instructions(payload: InstructionsImage, elder_id: int | None = None,
                           db: Session = Depends(get_db),
                           current: User = Depends(get_current_user)):
    resolve_elder_id(db, current, elder_id)
    try:
        text = recognize_image(payload.image_base64)
    except OcrUnavailableError as exc:
        raise HTTPException(status_code=503, detail=f"识别服务暂不可用：{exc}")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    compact = re.sub(r"[ \t]", "", text)
    name = re.search(r"(?:通用名称|通用名|药品名称)[：:]?([^\n【】]+)", compact)
    # 只提取明确写出的单次用量，避免把包装规格当成用量。
    dosage = re.search(r"(?:每次|一次)[：:]?([\d一二两三四五六七八九十半.～~\-至]+(?:毫克|克|毫升|mg|ml|片|粒|颗|袋|支|滴))", compact, re.I)
    frequency = re.search(r"(?:每日|每天|一日|一天)[：:]?([\d一二两三四五六七八九十]+)次", compact)
    freq = f"每日{frequency.group(1)}次" if frequency else ""
    times = sorted({f"{int(h):02d}:{m}" for h, m in re.findall(
        r"(?<!\d)([01]?\d|2[0-3])[:：]([0-5]\d)(?!\d)", compact)})
    return {"ocr_text": text, "name": name.group(1).strip("：:。；;") if name else "",
            "dosage": dosage.group(1) if dosage else "", "frequency": freq, "times": times}

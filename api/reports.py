# 体检报告接口：上传体检单图片 -> 保存 -> OCR 识别 -> AI 大白话建议（禁诊断）

import os
import uuid
import base64

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import User, HealthReport
from db.schemas import HealthReportOut
from core.security import get_current_user
from core.ocr import recognize_image
from core.health_llm import report_advice
from core.report_parse import parse_metrics
from api.meds import resolve_elder_id

router = APIRouter(prefix="/api/reports", tags=["体检报告"])

UPLOAD_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads", "reports")
os.makedirs(UPLOAD_DIR, exist_ok=True)

ALLOWED_IMAGES = {"image/jpeg", "image/png", "image/webp"}


@router.post("/upload", response_model=HealthReportOut)
async def upload_report(file: UploadFile = File(..., description="体检单图片"),
                        elder_id: int | None = Form(None),
                        db: Session = Depends(get_db),
                        current: User = Depends(get_current_user)):
    """上传体检单，返回 OCR 文字与解读建议。"""
    if file.content_type not in ALLOWED_IMAGES:
        raise HTTPException(status_code=400,
                            detail=f"请上传 jpg/png/webp 图片，当前为 {file.content_type}")

    target = resolve_elder_id(db, current, elder_id)

    # 保存图片
    ext = os.path.splitext(file.filename)[1] or ".jpg"
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)
    content = await file.read()
    with open(filepath, "wb") as f:
        f.write(content)
    image_url = f"/api/reports/image/{filename}"

    # OCR + AI 建议（图片字节转 base64 复用 OCR 封装）
    image_b64 = base64.b64encode(content).decode()
    try:
        ocr_text = recognize_image(image_b64)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception:
        raise HTTPException(status_code=400, detail="图片识别失败，请重新拍摄清晰的体检单照片再试")
    # 先用代码精确判定每项 正常/偏高/偏低，再让 LLM 据此用大白话表达，避免数值误判
    metrics = parse_metrics(ocr_text)
    advice = report_advice(ocr_text, metrics)

    rec = HealthReport(
        elder_id=target,
        image_url=image_url,
        ocr_text=ocr_text,
        advice_text=advice,
    )
    db.add(rec)
    db.commit()
    db.refresh(rec)
    return rec


@router.get("", response_model=list[HealthReportOut])
def list_reports(elder_id: int | None = None,
                 db: Session = Depends(get_db),
                 current: User = Depends(get_current_user)):
    """查询体检报告历史。"""
    target = resolve_elder_id(db, current, elder_id)
    return (
        db.query(HealthReport)
        .filter(HealthReport.elder_id == target)
        .order_by(HealthReport.created_at.desc())
        .all()
    )


@router.get("/image/{filename}")
def get_image(filename: str):
    """查看体检单原图（无需鉴权）。"""
    filepath = os.path.join(UPLOAD_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="图片不存在")
    return FileResponse(filepath)

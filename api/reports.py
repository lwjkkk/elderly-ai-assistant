# 体检报告接口：上传体检单图片 -> 保存 -> OCR 识别 -> AI 大白话建议（禁诊断）

import os
import uuid
import base64
import asyncio
import logging
import time

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session, sessionmaker

from db.database import get_db
from db.models import User, HealthReport, ReportJob
from db.schemas import HealthReportOut
from core.security import get_current_user
from core.ocr import recognize_image, OcrUnavailableError, OcrNoTextError
from core.health_llm import report_advice
from core.report_parse import parse_metrics
from api.meds import resolve_elder_id

router = APIRouter(prefix="/api/reports", tags=["体检报告"])
logger = logging.getLogger(__name__)
MAX_REPORT_BYTES = 20 * 1024 * 1024

UPLOAD_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads", "reports")
os.makedirs(UPLOAD_DIR, exist_ok=True)


async def _read_report(file):
    content = await file.read(MAX_REPORT_BYTES + 1)
    if len(content) > MAX_REPORT_BYTES:
        raise HTTPException(status_code=413, detail="图片不能超过20MB，请压缩后上传。")
    return content

def _image_type(content: bytes) -> tuple[str, str] | None:
    """识别实际图片格式，兼容移动端将 multipart 文件标成 octet-stream。"""
    if content.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", ".jpg"
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png", ".png"
    if len(content) >= 12 and content[:4] == b"RIFF" and content[8:12] == b"WEBP":
        return "image/webp", ".webp"
    return None


@router.post("/upload", response_model=HealthReportOut)
async def upload_report(file: UploadFile = File(..., description="体检单图片"),
                        elder_id: int | None = Form(None),
                        db: Session = Depends(get_db),
                        current: User = Depends(get_current_user)):
    """上传体检单，返回 OCR 文字与解读建议。"""
    target = resolve_elder_id(db, current, elder_id)
    started = time.perf_counter()
    content = await _read_report(file)
    image_type = _image_type(content)
    if not image_type:
        received = file.content_type or "未知"
        raise HTTPException(status_code=400,
                            detail=f"请上传有效的 jpg/png/webp 图片，当前文件类型为 {received}")
    _, ext = image_type

    # OCR + AI 建议（图片字节转 base64 复用 OCR 封装）
    # 放到线程池执行，避免耗时的 OCR/LLM 调用阻塞事件循环
    image_b64 = base64.b64encode(content).decode("ascii")
    try:
        ocr_text = await asyncio.to_thread(recognize_image, image_b64)
    except OcrUnavailableError as e:
        raise HTTPException(status_code=500, detail=f"识别服务暂不可用，请稍后再试：{e}")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    # 先用代码精确判定每项 正常/偏高/偏低，再让 LLM 据此用大白话表达，避免数值误判
    ocr_seconds = time.perf_counter() - started
    metrics = parse_metrics(ocr_text)
    explain_started = time.perf_counter()
    advice = await asyncio.to_thread(report_advice, ocr_text, metrics)

    # 使用识别出的格式扩展名，不信任客户端传入的文件名/扩展名。
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)
    image_url = f"/api/reports/image/{filename}"
    with open(filepath, "wb") as f:
        f.write(content)

    rec = HealthReport(
        elder_id=target,
        image_url=image_url,
        ocr_text=ocr_text,
        advice_text=advice,
    )
    try:
        db.add(rec)
        db.commit()
        db.refresh(rec)
    except Exception:
        db.rollback()
        if os.path.exists(filepath):
            os.remove(filepath)
        raise
    out = HealthReportOut.model_validate(rec).model_dump()
    out["metrics"] = metrics
    logger.info("report_timing ocr_seconds=%.3f explain_seconds=%.3f total_seconds=%.3f",
                ocr_seconds, time.perf_counter() - explain_started, time.perf_counter() - started)
    return out


@router.post("/jobs", status_code=202)
async def create_report_job(file: UploadFile = File(...), elder_id: int | None = Form(None),
                            db: Session = Depends(get_db), current: User = Depends(get_current_user)):
    """快速接收图片，轮询 GET /jobs/{id} 获取阶段指标及最终报告。"""
    from services import report_jobs
    target = resolve_elder_id(db, current, elder_id)
    content = await _read_report(file)
    image_type = _image_type(content)
    if not image_type:
        raise HTTPException(status_code=400, detail="请上传有效的 jpg/png/webp 图片。")
    if not report_jobs.reserve_slot():
        raise HTTPException(status_code=429, detail="报告处理繁忙，请稍后再试。", headers={"Retry-After": "5"})
    job_id = uuid.uuid4().hex
    image_path = os.path.join(UPLOAD_DIR, job_id + image_type[1])
    try:
        with open(image_path, "wb") as stream:
            stream.write(content)
        job = ReportJob(id=job_id, elder_id=target, requested_by=current.id,
                        status="queued", image_path=image_path)
        db.add(job)
        db.commit()
    except Exception:
        db.rollback()
        report_jobs.release_slot()
        if os.path.exists(image_path):
            os.remove(image_path)
        raise
    try:
        report_jobs.submit(sessionmaker(bind=db.get_bind()), job_id)
    except Exception:
        db.delete(job)
        db.commit()
        if os.path.exists(image_path):
            os.remove(image_path)
        raise HTTPException(status_code=503, detail="报告任务暂不可用，请稍后再试。")
    return {"job_id": job_id, "status": "queued", "poll_after_ms": 1500}


@router.get("/jobs/{job_id}")
def get_report_job(job_id: str, db: Session = Depends(get_db), current: User = Depends(get_current_user)):
    job = db.get(ReportJob, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="任务不存在。")
    resolve_elder_id(db, current, job.elder_id)  # 每次读取重新核查绑定、年龄与分享规则。
    result = None
    if job.status == "completed" and job.report_id:
        report = db.get(HealthReport, job.report_id)
        if report is None:
            raise HTTPException(status_code=410, detail="对应报告已删除。")
        result = HealthReportOut.model_validate(report).model_dump(mode="json")
        result["metrics"] = job.metrics or []
    return {"job_id": job.id, "status": job.status, "poll_after_ms": 1500,
            "ocr_text": job.ocr_text, "metrics": job.metrics or [],
            "timings": job.timings or {}, "error": job.error, "report": result}


@router.get("", response_model=list[HealthReportOut])
def list_reports(elder_id: int | None = None,
                 db: Session = Depends(get_db),
                 current: User = Depends(get_current_user)):
    """查询体检报告历史。"""
    target = resolve_elder_id(db, current, elder_id)
    records = (
        db.query(HealthReport)
        .filter(HealthReport.elder_id == target)
        .order_by(HealthReport.created_at.desc())
        .all()
    )
    result = []
    for rec in records:
        out = HealthReportOut.model_validate(rec).model_dump()
        out["metrics"] = parse_metrics(rec.ocr_text or "")
        result.append(out)
    return result


@router.get("/image/{filename}")
def get_image(filename: str,
              db: Session = Depends(get_db),
              current: User = Depends(get_current_user)):
    """查看体检单原图（需登录且为数据所有者或绑定家属）。"""
    # 校验文件归属：通过 image_url 反查 HealthReport 记录
    image_url = f"/api/reports/image/{filename}"
    report = db.query(HealthReport).filter(HealthReport.image_url == image_url).first()
    if not report:
        raise HTTPException(status_code=404, detail="图片不存在")
    # 权限：老人本人 / 已绑定家属才能查看
    resolve_elder_id(db, current, report.elder_id)

    filepath = os.path.join(UPLOAD_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="图片不存在")
    return FileResponse(filepath)


@router.delete("/{report_id}")
def delete_report(report_id: int,
                  db: Session = Depends(get_db),
                  current: User = Depends(get_current_user)):
    """删除本人上传的报告及对应图片。"""
    record = db.query(HealthReport).filter(HealthReport.id == report_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="报告不存在")
    if record.elder_id != current.id:
        raise HTTPException(status_code=403, detail="只能删除本人上传的报告")
    image_path = os.path.join(UPLOAD_DIR, os.path.basename(record.image_url or ""))
    db.query(ReportJob).filter(ReportJob.report_id == report_id).delete(synchronize_session=False)
    db.delete(record)
    db.commit()
    if os.path.isfile(image_path):
        os.remove(image_path)
    return {"ok": True}

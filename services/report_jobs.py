"""Bounded report processing with durable stages; workers own their DB sessions."""
import base64
import logging
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from db.models import HealthReport, ReportJob
from core.report_ocr import recognize_report
from core.ocr import OcrNoTextError, OcrUnavailableError
from core.health_llm import report_advice
from core.report_quality import ReportRetakeRequired

logger = logging.getLogger(__name__)
_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="report-job")
_slots = threading.BoundedSemaphore(4)  # 一项运行、最多三项等待，避免 CPU/内存被图片任务打满。


def reserve_slot():
    return _slots.acquire(blocking=False)


def release_slot():
    _slots.release()


def submit(factory, job_id):
    try:
        return _executor.submit(_run, factory, job_id)
    except Exception:
        release_slot()
        raise


def recover_interrupted(factory):
    """仅在单实例启动时执行，旧任务不自动重复生成报告。"""
    with factory() as db:
        jobs = db.query(ReportJob).filter(ReportJob.status.in_(["queued", "ocr", "explaining"])).all()
        for job in jobs:
            job.status = "failed"
            job.error = "服务重启导致任务中断，请重新上传。"
            if job.image_path and os.path.isfile(job.image_path):
                os.remove(job.image_path)
            job.image_path = None
        db.commit()


def _run(factory, job_id):
    started = time.perf_counter()
    timings = {}
    image_path = None
    try:
        with factory() as db:
            job = db.get(ReportJob, job_id)
            if job is None:
                return
            image_path = job.image_path
            job.status = "ocr"
            db.commit()
            with open(image_path, "rb") as stream:
                encoded = base64.b64encode(stream.read()).decode("ascii")
            t = time.perf_counter()
            text, details = recognize_report(encoded)
            timings["ocr_seconds"] = round(time.perf_counter() - t, 3)
            t = time.perf_counter()
            metrics = details["metrics"]
            timings["parse_seconds"] = round(time.perf_counter() - t, 3)
            job.ocr_text, job.metrics = text, metrics
            job.ocr_details = details
            job.timings = dict(timings)
            job.status = "explaining"
            db.commit()  # 指标可先供客户端读取，无需等模型完成。
            t = time.perf_counter()
            advice = report_advice(text, metrics)
            timings["explain_seconds"] = round(time.perf_counter() - t, 3)
            report = HealthReport(elder_id=job.elder_id,
                                  image_url="/api/reports/image/" + os.path.basename(image_path),
                                  ocr_text=text, advice_text=advice, ocr_details=details)
            db.add(report)
            db.flush()
            job.report_id, job.status = report.id, "completed"
            timings["total_seconds"] = round(time.perf_counter() - started, 3)
            job.timings = dict(timings)
            db.commit()  # 报告与任务成功状态原子写入。
            logger.info("report_job_timing job=%s timings=%s", job_id, timings)
    except Exception as exc:
        logger.exception("Report job failed: %s", job_id)
        if image_path and os.path.isfile(image_path):
            try:
                os.remove(image_path)
            except OSError:
                logger.exception("Failed to remove interrupted report image: %s", job_id)
        with factory() as db:
            job = db.get(ReportJob, job_id)
            if job is not None:
                job.status = "failed"
                if isinstance(exc, ReportRetakeRequired):
                    job.ocr_details = exc.document
                    job.metrics = exc.document.get('metrics',[])
                    job.error = str(exc)
                elif isinstance(exc, OcrUnavailableError):
                    job.error = "识别服务暂不可用，请稍后重试。"
                elif isinstance(exc, (OcrNoTextError, ValueError)) and not job.metrics:
                    job.error = str(exc)
                else:
                    job.error = "报告处理失败；已识别的指标可供核对，请稍后重新上传。"
                job.image_path = None
                job.timings = {**timings, "total_seconds": round(time.perf_counter() - started, 3)}
                db.commit()
    finally:
        release_slot()

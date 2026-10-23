"""Report-only OCR: spatial evidence, bounded local retries, conservative parsing."""
import os
import re
from copy import deepcopy
from statistics import median

from core.ocr import (_decode_image, recognize_blocks, _reconstruct_table_rows,
                      _join_sorted, OcrNoTextError)
from core.report_parse import parse_metrics
from core.report_parse import _UNIT

VERSION = "report-ocr-1.0"
LOW_CONFIDENCE = 0.90  # Operational review threshold, not calibrated accuracy.
MAX_RETRIES = 3


def _spatial_rows(blocks, width):
    """Remove local baseline tilt for row matching; evidence stays in original pixels."""
    slopes = []
    for b in blocks:
        p = b.get("polygon")
        if p and len(p) >= 4 and p[1][0] - p[0][0] > 50:
            slope = (p[1][1] - p[0][1]) / (p[1][0] - p[0][0])
            if abs(slope) < .15:
                slopes.append((b["cy"], slope))
    adjusted = []
    for index, b in enumerate(blocks):
        local = [s for y, s in slopes if abs(y - b["cy"]) < 150]
        slope = median(local) if local else 0
        adjusted.append({**b, "cy": b["cy"] - slope * b["cx"], "_index": index})
    return [[blocks[b["_index"]] for b in row]
            for row in _reconstruct_table_rows(adjusted, width)]


def _warnings(arr):
    import cv2
    gray = cv2.cvtColor(arr, cv2.COLOR_BGR2GRAY)
    warnings = []
    if min(arr.shape[:2]) < 600:
        warnings.append("图片较小，小字可能不清晰；建议上传原图")
    if cv2.Laplacian(gray, cv2.CV_64F).var() < 35:
        warnings.append("图片可能模糊，请核对小数点和数字")
    if float(gray.mean()) < 55:
        warnings.append("图片偏暗，建议在均匀光线下重新拍摄")
    return warnings


def _retry_row(arr, row):
    """Retry only a low-confidence row. Different text remains disputed, never guessed."""
    import cv2
    points = [p for b in row for p in (b.get("polygon") or [])]
    if not points:
        return None
    xs, ys = zip(*points)
    pad = max(5, int(max(b["h"] for b in row) * .4))
    x0, y0 = max(0, int(min(xs)) - pad), max(0, int(min(ys)) - pad)
    x1, y1 = min(arr.shape[1], int(max(xs)) + pad), min(arr.shape[0], int(max(ys)) + pad)
    crop = arr[y0:y1, x0:x1]
    if crop.size == 0:
        return None
    # Upscale without binarization; keep decimal dots and comparison symbols.
    crop = cv2.resize(crop, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC)
    blocks = recognize_blocks(crop)
    return {"text": _join_sorted(blocks), "crop": [x0, y0, x1, y1],
            "blocks": blocks, "coordinate_space": "crop_scaled_1.5"}


def recognize_report(image_base64):
    arr = _decode_image(image_base64)
    if min(arr.shape[:2]) < 32:
        raise ValueError("图片尺寸过小，请上传完整、清晰的体检报告原图")
    if arr.shape[0] * arr.shape[1] > 40_000_000:
        raise ValueError("图片像素过大，请上传不超过4000万像素的清晰报告图片")
    blocks = recognize_blocks(arr)
    if not blocks:
        raise OcrNoTextError("照片中未识别到文字，请上传清晰、完整的体检报告")
    rows = []
    retries = 0
    for group in _spatial_rows(blocks, arr.shape[1]):
        group = sorted(group, key=lambda b: b["cx"])
        unit_positions = [i for i, b in enumerate(group) if _UNIT.fullmatch(b["text"].strip())]
        range_positions = [i for i, b in enumerate(group) if re.search(r"\d\s*(?:-|~|至)\s*\d", b["text"])]
        # OCR often reads the result flag ↑ as 1/I/t; this separate post-unit flag
        # is retained as evidence but cannot change numeric comparison or confidence.
        relevant = [b for i, b in enumerate(group)
                    if not (b["text"].strip() in ("1", "I", "t", "↑", "↓")
                            and any(u < i for u in unit_positions)
                            and any(r > i for r in range_positions))]
        scores = [b["confidence"] for b in relevant if b.get("confidence") is not None]
        confidence = min(scores) if scores and len(scores) == len(relevant) else None
        row = {"text": _join_sorted(group), "blocks": group, "confidence": confidence,
               "needs_review": confidence is None or confidence < LOW_CONFIDENCE
                               or any(not b.get("polygon") for b in group)}
        if row["needs_review"] and re.search(r"\d", row["text"]) and retries < MAX_RETRIES:
            retries += 1
            try:
                row["retry"] = _retry_row(arr, group)
            except Exception:
                # A retry failure does not invalidate the successful initial recognition.
                row["retry_error"] = "局部重识别失败，请对照原图核对"
        rows.append(row)
    document = {"version": VERSION, "width": int(arr.shape[1]), "height": int(arr.shape[0]),
                "coordinate_space": "original_image_pixels", "rows": rows,
                "warnings": _warnings(arr), "retry_count": retries,
                "models": {"det": os.getenv("OCR_DET_MODEL", "PP-OCRv6_medium_det"),
                           "rec": os.getenv("OCR_REC_MODEL", "PP-OCRv6_medium_rec")}}
    text = "\n".join(r["text"] for r in rows)
    document["metrics"] = parse_report_document(document)
    return text, document


def parse_report_document(document):
    metrics = []
    for index, row in enumerate(document["rows"]):
        if (not re.search(r"\d", row["text"])
                or re.search(r"姓名|送检|检验者|审核|检验时间|小红书|编号|条码|联系电话", row["text"])):
            continue
        # Never merge a different spatial row or attach an orphan range across columns.
        for metric in parse_metrics(row["text"]):
            if not metric.get("code"):
                continue
            metric.update(source_line=index, source_lines=[index],
                          ocr_confidence=row["confidence"], source_blocks=row["blocks"],
                          ocr_pipeline_version=VERSION)
            reasons = []
            if row["needs_review"]:
                reasons.append("OCR 置信度不足或缺少坐标证据，请对照原图核对")
            retry = row.get("retry")
            if retry and re.sub(r"\s", "", retry["text"]) != re.sub(r"\s", "", row["text"]):
                reasons.append("局部重识别与原始识别不一致")
            # Multiple metric-looking names before distinct numeric results are ambiguous.
            if len(re.findall(r"\d+(?:\.\d+)?\s*(?:mmol/L|g/L|U/L|%)", row["text"])) > 1:
                reasons.append("同一行存在多组结果，列对应关系需核对")
            if reasons:
                metric["status"] = "unparsed"
                metric["verification_reason"] = "；".join(reasons)
            metric["needs_review"] = metric["status"] == "unparsed"
            metrics.append(metric)
    return metrics


def report_metrics(report):
    """One persisted result for upload, history and family sync; legacy reports still work."""
    details = getattr(report, "ocr_details", None)
    if isinstance(details, dict) and isinstance(details.get("metrics"), list):
        return deepcopy(details["metrics"])
    return parse_metrics(report.ocr_text or "")

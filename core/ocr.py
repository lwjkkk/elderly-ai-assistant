# OCR 封装：基于 PaddleOCR 识别药盒/截图文字
# 针对老人拍照场景做了适配：开启角度分类（倾斜）、中文模型；低清反光依赖模型自身能力。
# 设计为懒加载：import 本模块不依赖 paddle，真正调用时才加载，未安装则给出明确提示。

import base64
import logging
import re

# 必须在 import paddleocr/paddlepaddle 之前先加载 torch：
# paddle 先加载的 OpenMP(libiomp5md) 等 DLL 会与 torch 的 shm.dll 冲突，
# 导致 WinError 127；先 import torch 可规避该 DLL 加载顺序问题。
import torch  # noqa: F401

logger = logging.getLogger(__name__)

_ocr = None


def _get_ocr():
    """懒加载 PaddleOCR 实例（首次调用较慢，会加载模型）。"""
    global _ocr
    if _ocr is None:
        try:
            from paddleocr import PaddleOCR
        except ImportError:
            raise RuntimeError(
                "未安装 PaddleOCR，请先执行：pip install paddleocr paddlepaddle"
            )
        # use_angle_cls=True 处理倾斜；lang='ch' 中英文混合
        # enable_mkldnn=True 开启 Intel oneDNN 加速，CPU 推理更快；
        # 前提是 paddlepaddle 2.6 与 paddleocr 2.10 版本配套（paddle 3.x 下 oneDNN 不兼容）
        _ocr = PaddleOCR(use_angle_cls=True, lang="ch", show_log=False,
                          enable_mkldnn=True)
    return _ocr


def _decode_image(image_base64: str):
    """把 base64 图片解码为 OpenCV BGR 图像数组。"""
    import numpy as np
    import cv2

    # 兼容可能带 data:image/...;base64, 前缀的情况
    if "," in image_base64 and image_base64.strip().startswith("data:"):
        image_base64 = image_base64.split(",", 1)[1]
    raw = base64.b64decode(image_base64)
    arr = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
    if arr is None:
        raise ValueError("图片解码失败，请确认上传的是有效图片")
    return arr


def _group_lines_by_position(blocks):
    """把文本块按坐标重建为"行"：先按纵向(y)聚类成行，行内按横向(x)排序。
    blocks: [(cy, cx, height, text), ...]；这样表格同一指标的 代号/结果/箭头/参考值
    会落在同一行，避免参考值上下错位、箭头找不到归属。"""
    blocks = sorted(blocks, key=lambda b: b[0])
    if not blocks:
        return []

    heights = sorted(b[2] for b in blocks)
    med_h = heights[len(heights) // 2] or 10
    thresh = max(med_h * 0.6, 8)   # 纵向差距小于该行高阈值视为同一行

    rows = []
    cur = [blocks[0]]
    base = blocks[0][0]
    for b in blocks[1:]:
        if b[0] - base <= thresh:
            cur.append(b)
        else:
            rows.append(cur)
            cur = [b]
            base = b[0]
    rows.append(cur)

    lines = []
    for row in rows:
        row.sort(key=lambda b: b[1])
        joined = " ".join(b[3] for b in row if b[3])
        if joined:
            lines.append(joined)
    return lines


def _merge_name_and_data(lines):
    """合并错位的"名称行+数字行"。
    拍照透视常使左侧"代号+中文名称"比右侧"结果+参考值"偏上半行，被拆成两行。
    若某行去掉开头序号后不含任何数字，判定为纯名称行，与下一行(数字)合并。"""
    merged = []
    i = 0
    while i < len(lines):
        cur = lines[i]
        rest = re.sub(r"^\d+\s*", "", cur)
        is_name_line = not re.search(r"\d", rest)
        if is_name_line and i + 1 < len(lines):
            merged.append(f"{cur} {lines[i + 1]}")
            i += 2
        else:
            merged.append(cur)
            i += 1
    return merged


def recognize_image(image_base64: str) -> str:
    """识别图片中的文字，按版面坐标重建为逐行文本（适合表格类化验单/药盒）。"""
    arr = _decode_image(image_base64)
    ocr = _get_ocr()

    # PaddleOCR 2.x 用 .ocr()；3.x 部分版本改为 .predict()，这里做兼容
    try:
        result = ocr.ocr(arr, cls=True)
    except AttributeError:
        result = ocr.predict(arr)

    lines = []
    # 结构：[ [ [box, (text, score)], ... ] ]（predict 版本可能是 dict 列表）
    for page in result or []:
        # 3.x：page 可能是包含 rec_texts 的字典（无坐标，退化为纯文本）
        if isinstance(page, dict):
            lines.extend(page.get("rec_texts") or [])
            continue

        blocks = []
        for item in page or []:
            try:
                box, (text, _score) = item[0], item[1]
                xs = [p[0] for p in box]
                ys = [p[1] for p in box]
                cy, cx = sum(ys) / 4, sum(xs) / 4
                height = max(ys) - min(ys)
                blocks.append((cy, cx, height, text))
            except (IndexError, TypeError):
                continue
        lines.extend(_group_lines_by_position(blocks))

    lines = _merge_name_and_data(lines)
    text = "\n".join(t for t in lines if t)
    if not text:
        logger.warning("OCR 未识别到文字，可能是图片过于模糊")
    return text

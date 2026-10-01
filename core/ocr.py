# OCR 封装：基于 PaddleOCR 识别药盒/截图文字
# 针对老人拍照场景做了适配：开启角度分类（倾斜）、中文模型；低清反光依赖模型自身能力。
# 设计为懒加载：import 本模块不依赖 paddle，真正调用时才加载，未安装则给出明确提示。

import base64
import logging

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
        _ocr = PaddleOCR(use_angle_cls=True, lang="ch", show_log=False)
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


def recognize_image(image_base64: str) -> str:
    """识别图片中的文字，返回拼接后的纯文本。"""
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
        # 3.x：page 可能是包含 rec_texts 的字典
        if isinstance(page, dict):
            texts = page.get("rec_texts") or []
            lines.extend(texts)
            continue
        for item in page or []:
            try:
                lines.append(item[1][0])
            except (IndexError, TypeError):
                continue

    text = "\n".join(t for t in lines if t)
    if not text:
        logger.warning("OCR 未识别到文字，可能是图片过于模糊")
    return text

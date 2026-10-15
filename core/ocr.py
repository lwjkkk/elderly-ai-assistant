# OCR 封装：基于 PaddleOCR 识别药盒/截图文字
# 针对老人拍照场景做了适配：开启角度分类（倾斜）、中文模型；低清反光依赖模型自身能力。
# 设计为懒加载：import 本模块不依赖 paddle，真正调用时才加载，未安装则给出明确提示。

import base64
import logging
import os
import re
import sys

from config.settings import OCR_MODEL_DIR, OCR_LANG, OCR_USE_GPU

logger = logging.getLogger(__name__)

_ocr = None
_dll_directory_handles = []


def _configure_windows_dll_search() -> None:
    """Expose the active conda runtime DLL directories to torch/paddle on Windows."""
    if os.name != "nt" or _dll_directory_handles:
        return
    candidates = (
        os.path.join(sys.prefix, "Library", "bin"),
        os.path.join(sys.prefix, "Scripts"),
        os.path.join(sys.prefix, "Lib", "site-packages", "torch", "lib"),
    )
    for directory in candidates:
        if os.path.isdir(directory):
            try:
                # Windows requires keeping the returned handle alive for the DLL search path.
                _dll_directory_handles.append(os.add_dll_directory(directory))
            except OSError as e:
                logger.warning("无法注册 OCR 运行库目录 %s：%s", directory, e)


class OcrUnavailableError(RuntimeError):
    """OCR 服务端不可用：依赖未装、模型文件缺失/无法初始化。
    这是后端环境问题，应返回 500，不能让用户重拍照片。"""


class OcrNoTextError(ValueError):
    """图片本身没有可识别文字（模糊/无文字/不是目标照片）。
    这是业务输入问题，返回 400，提示用户重拍。"""


def _get_ocr():
    """懒加载 PaddleOCR 实例（首次调用较慢，会加载模型）。
    模型目录统一指向 OCR_MODEL_DIR 下的纯英文子目录，规避中文路径打不开模型文件的问题。"""
    global _ocr
    if _ocr is None:
        try:
            # PaddleOCR 2.x 的图像增强依赖可能导入 torch。先加载它以降低 OpenMP DLL 冲突，
            # 但延迟到首次 OCR 请求，避免 torch 环境故障阻断整个后端启动。
            _configure_windows_dll_search()
            if os.name == "nt":
                import torch  # noqa: F401  # Windows 下提前加载避免 OpenMP DLL 冲突
            from paddleocr import PaddleOCR
        except Exception as e:
            raise OcrUnavailableError(
                f"OCR 依赖不可用（请检查 PaddleOCR、PaddlePaddle、PyTorch 安装）：{e}"
            ) from e

        # 纯英文模型目录，Paddle 推理引擎才能正确打开模型文件
        det_dir = os.path.join(OCR_MODEL_DIR, "det")
        rec_dir = os.path.join(OCR_MODEL_DIR, "rec")
        cls_dir = os.path.join(OCR_MODEL_DIR, "cls")
        try:
            os.makedirs(OCR_MODEL_DIR, exist_ok=True)
            _ocr = PaddleOCR(
                use_angle_cls=True,
                lang=OCR_LANG,
                show_log=False,
                enable_mkldnn=not OCR_USE_GPU,
                det_model_dir=det_dir,
                rec_model_dir=rec_dir,
                cls_model_dir=cls_dir,
            )
        except Exception as e:
            _ocr = None
            raise OcrUnavailableError(
                f"OCR 模型初始化失败，请检查 OCR_MODEL_DIR={OCR_MODEL_DIR} 下模型文件是否完整：{e}"
            ) from e
    return _ocr


def _decode_image(image_base64: str):
    """把 base64 图片解码为 OpenCV BGR 图像数组。"""
    try:
        import numpy as np
        import cv2
    except Exception as e:
        raise OcrUnavailableError(f"OCR 图像处理依赖不可用：{e}") from e

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
    """识别图片中的文字，按版面坐标重建为逐行文本（适合表格类化验单/药盒）。

    异常约定：
    - OcrUnavailableError：后端 OCR 环境/模型问题（调用方返回 500）
    - OcrNoTextError / ValueError：图片本身问题（调用方返回 400）
    """
    arr = _decode_image(image_base64)
    ocr = _get_ocr()

    # PaddleOCR 2.x 用 .ocr()；3.x 部分版本改为 .predict()，这里做兼容
    try:
        try:
            result = ocr.ocr(arr, cls=True)
        except AttributeError:
            result = ocr.predict(arr)
    except Exception as e:
        # 推理阶段模型文件打不开/磁盘错误等属于服务端问题，不是用户照片问题
        raise OcrUnavailableError(f"OCR 推理失败：{e}") from e

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
    if not text.strip():
        raise OcrNoTextError("照片中未识别到文字，请重拍一张清晰、光线充足的照片")
    return text


def verify_ocr_ready() -> None:
    """启动自检：初始化预测器并用内存空白图执行一次推理，不读写测试图片文件。"""
    ocr = _get_ocr()
    try:
        import cv2
        import numpy as np

        probe = np.full((128, 256, 3), 255, dtype=np.uint8)
        try:
            ocr.ocr(probe, cls=True)
        except AttributeError:
            ocr.predict(probe)
    except Exception as e:
        raise OcrUnavailableError(f"OCR 启动自检推理失败：{e}") from e

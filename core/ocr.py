# OCR 封装：基于 PaddleOCR 识别药盒/截图文字
# 通用识别保留坐标与置信度；体检报告质量检查和局部重识别在 report_ocr.py。
# 设计为懒加载：import 本模块不依赖 paddle，真正调用时才加载，未安装则给出明确提示。

import base64
import logging
import os
import re
import sys
import threading

from config.settings import OCR_MODEL_DIR, OCR_USE_GPU

logger = logging.getLogger(__name__)

_ocr = None
_ocr_lock = threading.RLock()
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


def _get_ocr_unlocked():
    """懒加载 PaddleOCR 实例（首次调用较慢，会加载模型）。
    模型名称固定；自定义权重通过 OCR_DET_MODEL_DIR/OCR_REC_MODEL_DIR 显式配置。"""
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

        # paddleocr 3.x（基于 PaddleX）：通过 lang 自动下载官方中文模型并缓存。
        # 关闭 mkldnn/onednn：paddle 3.x 对 PP-OCRv6 的 onednn 推理存在未实现算子，CPU 上禁用后稳定。
        try:
            os.makedirs(OCR_MODEL_DIR, exist_ok=True)
            _ocr = PaddleOCR(
                use_doc_orientation_classify=False,
                use_doc_unwarping=False,
                use_textline_orientation=False,
                text_detection_model_name=os.getenv("OCR_DET_MODEL", "PP-OCRv6_medium_det"),
                text_recognition_model_name=os.getenv("OCR_REC_MODEL", "PP-OCRv6_medium_rec"),
                **_model_directories(),
                device="gpu:0" if OCR_USE_GPU else "cpu",
                text_rec_score_thresh=0.0,
                enable_mkldnn=False,
            )
        except Exception as e:
            _ocr = None
            raise OcrUnavailableError(
                f"OCR 模型初始化失败（paddleocr 3.x 自动下载模型）：{e}"
            ) from e
    return _ocr


def _model_directories():
    """Only explicitly configured v3 weights; never silently load legacy v2 directories."""
    options = {}
    for kind, parameter in (("DET", "text_detection_model_dir"), ("REC", "text_recognition_model_dir")):
        directory = os.getenv(f"OCR_{kind}_MODEL_DIR")
        if directory:
            if not os.path.isdir(directory):
                raise ValueError(f"OCR_{kind}_MODEL_DIR 不存在")
            options[parameter] = directory
    return options


def _get_ocr():
    with _ocr_lock:
        return _get_ocr_unlocked()


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
    if not raw:
        # 空内容（含全无效 base64 字符被忽略后的结果）不是有效图片，属于输入错误。
        raise ValueError("图片解码失败，请确认上传的是有效图片")
    try:
        arr = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
    except cv2.error as e:
        # OpenCV 对空/损坏 buf 可能直接抛 cv2.error（而非返回 None），统一视为输入错误。
        raise ValueError("图片解码失败，请确认上传的是有效图片") from e
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


def _group_rows(blocks):
    """把带坐标的文本块按纵向(y)聚类成行。blocks: [{text,cx,cy,h}, ...]。"""
    if not blocks:
        return []
    blocks = sorted(blocks, key=lambda b: b["cy"])
    heights = sorted(b["h"] for b in blocks)
    med_h = heights[len(heights) // 2] or 10
    # 行内块纵向差应小于"行高本身"；阈值放宽到中位行高，避免同一逻辑行被微抖拆分。
    thresh = max(med_h, 10)
    rows = []
    cur = [blocks[0]]
    base = blocks[0]["cy"]
    for b in blocks[1:]:
        if b["cy"] - base <= thresh:
            cur.append(b)
        else:
            rows.append(cur)
            cur = [b]
            base = b["cy"]
    rows.append(cur)
    return rows


def _detect_two_columns(blocks, image_w: float) -> float | None:
    """检测是否存在左右双栏表格结构，返回分栏阈值(cx/width，0~1)或 None(单栏)。
    判定：存在≥3 行"每行≥6 块、块横向跨全宽(左端<0.35、右端>0.65)"的数据行，
    说明是左右对称的体检表（左右各 4 列：名称/结果/单位/范围）。
    用这些行的块 cx 中位数(约在栏间缝)的中位数作栏界。药盒等无此规则结构则不触发。"""
    rows = _group_rows(blocks)
    cross = []
    for row in rows:
        cxs = sorted(b["cx"] / image_w for b in row)
        names = [b for b in row if _is_indicator_name(b["text"])]
        if (len(row) >= 6 and cxs[0] < 0.35 and cxs[-1] > 0.65
                and any(b["cx"] / image_w < 0.4 for b in names)
                and any(0.5 <= b["cx"] / image_w < 0.8 for b in names)):
            cross.append(cxs[len(cxs) // 2])
    if len(cross) < 3:
        return None
    cross.sort()
    med = cross[len(cross) // 2]
    # 中缝物理位置稳定在 0.5 附近；OCR 抖动会使中位数偏移，夹紧避免右栏名称漏进左栏。
    return min(max(med, 0.45), 0.55)


# 体检单里不属于"指标名"的噪音词（表头、个人信息、标题等）
_NAME_NOISE = ("姓名", "性别", "年龄", "门诊", "科室", "临床诊断", "样本类型", "样本", "备注",
               "报告单", "检验报告", "编号", "No", "检验项目", "结果", "单位", "参考范围",
               "参考值", "项目", "指标", "血清", "溶血", "乳糜", "黄疸")
_NAME_NUM_CN = "〇一二三四五六七八九十百千万"


def _is_indicator_name(text: str) -> bool:
    """判定文本块是否为体检指标的"名称块"（用于做行锚）。
    支持中文、英文缩写及 HbA1c 等含数字名称，排除表头和个人信息。"""
    t = (text or "").strip()
    if not t:
        return False
    if "+" in t:                       # 标题行，如"淀粉酶+肝功能+血糖+血脂6项..."
        return False
    if "：" in t or ":" in t:          # "姓名：王楼"等
        return False
    cn = re.findall(r"[\u4e00-\u9fff]", t)
    if not cn:
        return bool(re.fullmatch(r"(?:HbA1c|[A-Z]{2,6}(?:[-/][A-Z0-9]{1,4})?|25[- ]?OH[- ]?D)", t))
    if len(cn) < 2 or len(cn) > 16:
        return False
    if any(w in t for w in _NAME_NOISE):
        return False
    return True


def _split_by_name_anchors(col_blocks):
    """把单栏块按"名称块 cy"分行：名称块决定行序，值/单位/范围块归到 cy 最近的名称行。
    离所有名称行都过远（头部 title/表头/个人信息、或尾部）的块单独按 y 分行，避免污染指标行。
    用于行距不均匀、单纯 y 聚类会把相邻行合并/拆分的拍照表格（尤其中右栏）。"""
    candidates = [b for b in col_blocks if _is_indicator_name(b["text"])]
    chinese = [b for b in candidates if re.search(r"[\u4e00-\u9fff]", b["text"])]
    anchors = chinese or candidates
    if not anchors:
        return _group_rows(col_blocks)
    anchors.sort(key=lambda b: b["cy"])
    gaps = [anchors[i + 1]["cy"] - anchors[i]["cy"] for i in range(len(anchors) - 1)]
    if gaps:
        sg = sorted(gaps)
        row_gap = sg[len(sg) // 2]
    else:
        h = sorted(b["h"] for b in col_blocks)
        row_gap = h[len(h) // 2] or 20
    heights = sorted(b["h"] for b in col_blocks)
    thresh = max(min(row_gap * 0.48, heights[len(heights) // 2] * 1.2), 8)
    rows = [[] for _ in anchors]
    amap = {id(b): i for i, b in enumerate(anchors)}
    assigned = set()
    for b in col_blocks:
        if id(b) in amap:
            rows[amap[id(b)]].append(b)
            assigned.add(id(b))
        else:
            i = min(range(len(anchors)), key=lambda k: abs(b["cy"] - anchors[k]["cy"]))
            if abs(b["cy"] - anchors[i]["cy"]) <= thresh:
                rows[i].append(b)
                assigned.add(id(b))
    # 头部/尾部/远离锚点的块：单独按 y 分行，前部(标题/表头/个人信息)在前，后部(签名/日期)在后
    leftover = [b for b in col_blocks if id(b) not in assigned]
    head = [b for b in leftover if b["cy"] < anchors[0]["cy"] - thresh]
    tail = [b for b in leftover if b["cy"] > anchors[-1]["cy"] + thresh]
    mid = [b for b in leftover if b not in head and b not in tail]
    result = _group_rows(head) + rows + _group_rows(tail)
    if mid:
        result = _group_rows(head) + rows + _group_rows(mid) + _group_rows(tail)
    return result


def _reconstruct_table_rows(blocks, image_w: float):
    """把带坐标的文本块重建为表格行文本：
    - 单栏：全局 y 分行，行内按 x 排序拼接；
    - 双栏：按栏界拆左右。左栏行距正常用 y 聚类；右栏行距小易合并错位，用"名称块锚定"分行。
      栏内行按 x 排序拼接。
    这样真实双栏体检单每条指标(名称+值+单位+参考范围)独占一行，解析层无需坐标即可正确配对。"""
    ratio = _detect_two_columns(blocks, image_w)
    if ratio is None:
        return _group_rows(blocks)
    left = [b for b in blocks if b["cx"] / image_w < ratio]
    right = [b for b in blocks if b["cx"] / image_w >= ratio]
    lines = []
    # 左右栏都按"名称块锚定"分行（ratio 已夹紧到中缝，右栏名称不会漏进左栏抢块）。
    for col in (left, right):
        for row in _split_by_name_anchors(col):
            if row:
                lines.append(row)
    return lines


def _reconstruct_table_lines(blocks, image_w: float) -> list[str]:
    return [_join_sorted(row) for row in _reconstruct_table_rows(blocks, image_w) if row]


def _join_sorted(row) -> str:
    row = sorted(row, key=lambda b: b["cx"])
    return " ".join(b["text"] for b in row if b["text"]).strip()


def _merge_name_and_data(lines):
    """合并错位的"名称行+数字行"。
    拍照透视常使左侧"代号+中文名称"比右侧"结果+参考值"偏上半行，被拆成两行。
    若某行去掉开头序号后不含任何数字，判定为纯名称行，与下一行(数字)合并。"""
    merged = []
    i = 0
    while i < len(lines):
        cur = lines[i]
        rest = re.sub(r"^\d+\s*", "", cur)
        is_name_line = _is_indicator_name(rest) and not re.search(r"\d", rest)
        if (is_name_line and i + 1 < len(lines)
                and re.match(r"^\s*[<>≤≥]?\s*\d", lines[i + 1])):
            merged.append(f"{cur} {lines[i + 1]}")
            i += 2
        else:
            merged.append(cur)
            i += 1
    return merged


def recognize_blocks(arr):
    """Real OCR inference, preserving original-image coordinates and confidence."""
    with _ocr_lock:
        ocr = _get_ocr()
        try:
            result = list(ocr.predict(arr))
        except Exception as exc:
            raise OcrUnavailableError(f"OCR 推理失败：{exc}") from exc
    blocks = []
    for page in result:
        if not hasattr(page, "get"):
            raise OcrUnavailableError("OCR 返回结构不兼容，请使用 PaddleOCR 3.x")
        texts = page.get("rec_texts")
        polys = page.get("rec_polys")
        scores = page.get("rec_scores")
        if texts is None:
            continue
        for index, text in enumerate(texts):
            if not text:
                continue
            score = float(scores[index]) if scores is not None and index < len(scores) else None
            polygon = None
            if polys is not None and index < len(polys):
                polygon = [[float(x), float(y)] for x, y in polys[index]]
            if not polygon:
                # Preserve text but do not invent geometry or trust its table alignment.
                blocks.append({"text": str(text), "confidence": score, "polygon": None,
                               "cx": 0.0, "cy": float(index * 20), "h": 10.0})
                continue
            xs, ys = zip(*polygon)
            blocks.append({"text": str(text), "confidence": score, "polygon": polygon,
                           "cx": sum(xs) / len(xs), "cy": sum(ys) / len(ys),
                           "h": max(ys) - min(ys)})
    return blocks


def recognize_image(image_base64: str) -> str:
    """Compatibility text API for drug images; report pipeline uses structured blocks."""
    arr = _decode_image(image_base64)
    blocks = recognize_blocks(arr)
    blocks = [b for b in blocks if b["confidence"] is None or b["confidence"] >= .5]
    text = "\n".join(_reconstruct_table_lines(blocks, arr.shape[1]))
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
        with _ocr_lock:
            ocr.predict(probe)
    except Exception as e:
        raise OcrUnavailableError(f"OCR 启动自检推理失败：{e}") from e

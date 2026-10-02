# 体检指标解析与判定：从 OCR 逐行文本里提取 代号/结果/参考范围，用代码精确判断
# 正常/偏高/偏低，不依赖 LLM 做数值比较（LLM 对范围内数值容易误报）。

import re

# 参考范围，如 0--5.2 或 3. 9--6.11（OCR 可能在数字里夹空格）
_RANGE = re.compile(r"(\d+\s?\.?\s?\d*)\s*--\s*(\d+\s?\.?\s?\d*)")
# 项目代号：大写字母缩写，如 ALT、CK-MB、HDL
_CODE = re.compile(r"\b([A-Z]{1,4}(?:-[A-Z]{1,2})?)\b")


def _to_num(s: str) -> float:
    return float(s.replace(" ", ""))


def parse_metrics(ocr_text: str) -> list[dict]:
    """返回 [{code,result,lo,hi,status}]，status= normal/high/low。"""
    metrics = []
    for line in ocr_text.split("\n"):
        m = _RANGE.search(line)
        if not m:
            continue
        lo, hi = _to_num(m.group(1)), _to_num(m.group(2))

        code_m = _CODE.search(line)
        code = code_m.group(1) if code_m else None

        # 结果数字：范围之前出现的数字，去掉行首序号后取最后一个
        before = line[:m.start()]
        nums = re.findall(r"\d+\s?\.?\s?\d*", before)
        if not nums:
            continue
        result = _to_num(nums[-1])

        if result < lo:
            status = "low"
        elif result > hi:
            status = "high"
        else:
            status = "normal"

        metrics.append({"code": code, "result": result,
                        "lo": lo, "hi": hi, "status": status})

    # 同一代号可能因错位出现多行，保留能判定为 high/low 的那条，否则任取一条
    dedup = {}
    for item in metrics:
        key = item["code"]
        if key not in dedup or item["status"] != "normal":
            dedup[key] = item
    return list(dedup.values())


def format_metrics(metrics: list[dict]) -> str:
    """把判定结果整理成给 LLM 的"已核对事实"文本。"""
    labels = {"normal": "正常", "high": "偏高", "low": "偏低"}
    rows = []
    for it in metrics:
        rows.append(
            f"{it['code']}：结果{it['result']}，参考{it['lo']}~{it['hi']}，"
            f"程序判定为【{labels[it['status']]}】"
        )
    return "\n".join(rows)

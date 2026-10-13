# 体检指标解析与判定：从 OCR 逐行文本里提取 代号/结果/参考范围，用代码精确判断
# 正常/偏高/偏低，不依赖 LLM 做数值比较（LLM 对范围内数值容易误报）。
#
# 支持的参考范围格式（覆盖真实体检单常见写法与 OCR 误差）：
#   0--5.2、3. 9--6.11、3.9-6.1、2.8~5.2、3.9～6.1、3.9至6.1、3,9-6,1（逗号小数点）
# 未匹配到范围但行里有代号+数字的指标，标记为 unparsed（"未能核对"），
# 禁止把它们当作"全部正常"交给 LLM。

import re

# 数字：兼容 "3.9"、"3. 9"（点后空格）、"3,9"（逗号小数点，OCR 偶尔识别错）
_NUM = r"\d+(?:\s*[.,]\s*\s*\d+)?"

# 参考范围：数字 + 分隔符（-- 优先，其次 ~/～/至，最后单横线 -）+ 数字
# 注意 alternation 顺序：-- 必须排在 - 前面，否则 0--5.2 会被拆成 - 分隔
_RANGE = re.compile(
    rf"({_NUM})\s*(?:--|~|～|至|-)\s*({_NUM})"
)

# 项目代号：大写字母缩写，如 ALT、CK-MB、HDL、GLU、TC、TG
# 至少 2 个字母或含连字符，避免匹配单位中的单个 L / U / G 等
_CODE = re.compile(r"\b([A-Z]{2,6}(?:-[A-Z]{1,3})?)\b")

# 中文指标名：2~8 个连续中文字符（白细胞、血红蛋白、总胆固醇等）
_CN_NAME = re.compile(r"[\u4e00-\u9fff]{2,8}")

# 单位中含数字的模式：10^9/L、×10^9/L、10^12/L、10E9/L 等
# 提取结果前需先移除这些模式，避免把单位里的数字误认为结果值
_UNIT_WITH_NUM = re.compile(
    r"(?:[×xX]\s*)?\d+\s*[\^eE]\+?\d+\s*/\s*[A-Za-z%]+"
    r"|\d+\s*/\s*(?:HPF|dl|dL|UL|ul)"
)


def _to_num(s: str) -> float:
    """把 OCR 数字字符串转 float，兼容空格、逗号小数点。"""
    s = s.replace(" ", "").replace(",", ".")
    return float(s)


def _strip_units(text: str) -> str:
    """移除文本中含数字的单位表达式，防止单位数字被误提取为结果。"""
    return _UNIT_WITH_NUM.sub(" ", text)


def _extract_result(line: str, range_start: int) -> float | None:
    """从范围之前的文本里取结果数字：去掉行首序号和单位中的数字后取最后一个数字。"""
    before = line[:range_start]
    # 去掉行首序号（如 "1 ALT ..." 里的 "1"）
    before = re.sub(r"^\s*\d+[\.\、\)]?\s*", "", before)
    # 移除含数字的单位模式（如 10^9/L、×10^12/L），避免误取单位数字
    before = _strip_units(before)
    nums = re.findall(_NUM, before)
    if not nums:
        return None
    try:
        return _to_num(nums[-1])
    except ValueError:
        return None


def _extract_unparsed_result(line: str, name: str) -> float | None:
    """无参考范围时，从指标名称/代号之后提取最先出现的结果数值。"""
    # 先尝试精确匹配名称位置
    match = re.search(rf"(?:\b{re.escape(name)}\b|{re.escape(name)})", line)
    if not match:
        return None
    after = line[match.end():]
    # 移除含数字的单位模式
    after = _strip_units(after)
    nums = re.findall(_NUM, after)
    if not nums:
        return None
    try:
        return _to_num(nums[0])
    except ValueError:
        return None


def _extract_code(line: str) -> str | None:
    """提取指标代号（英文缩写）或中文名称。"""
    # 优先匹配英文代号（至少 2 个大写字母）
    m = _CODE.search(line)
    if m:
        return m.group(1)
    # 其次匹配中文指标名（2~8 个汉字）
    m = _CN_NAME.search(line)
    if m:
        return m.group(0)
    return None


def parse_metrics(ocr_text: str) -> list[dict]:
    """返回 [{code, result, lo, hi, status}]。
    status ∈ normal/high/low/unparsed。
    unparsed 表示这一行有指标代号+数字但没识别出参考范围，不能当作正常。"""
    metrics = []
    for line in ocr_text.split("\n"):
        line = line.strip()
        if not line:
            continue

        m = _RANGE.search(line)
        if m:
            try:
                lo = _to_num(m.group(1))
                hi = _to_num(m.group(2))
            except ValueError:
                continue
            result = _extract_result(line, m.start())
            code = _extract_code(line)
            if result is None:
                continue
            if result < lo:
                status = "low"
            elif result > hi:
                status = "high"
            else:
                status = "normal"
            metrics.append({"code": code, "result": result,
                            "lo": lo, "hi": hi, "status": status})
        else:
            # 没匹配到范围，但行里有名称/代号+数字 → 标记为未能核对
            code = _extract_code(line)
            if code and re.search(r"\d", line):
                metrics.append({"code": code, "result": _extract_unparsed_result(line, code),
                                "lo": None, "hi": None, "status": "unparsed"})

    # 同一代号可能因错行出现多条：优先保留能判定为 high/low 的，其次 normal，最后 unparsed
    rank = {"high": 3, "low": 3, "normal": 2, "unparsed": 1}
    dedup: dict[str, dict] = {}
    for item in metrics:
        key = item["code"] or f"_line_{len(dedup)}"
        if key not in dedup or rank[item["status"]] > rank[dedup[key]["status"]]:
            dedup[key] = item
    return list(dedup.values())


def format_metrics(metrics: list[dict]) -> str:
    """把判定结果整理成给 LLM 的"已核对事实"文本。"""
    labels = {"normal": "正常", "high": "偏高", "low": "偏低", "unparsed": "未能核对"}
    rows = []
    for it in metrics:
        if it["status"] == "unparsed":
            rows.append(f"{it['code']}：结果{it.get('result')}，未能识别参考范围，程序判定为【未能核对】")
        else:
            rows.append(
                f"{it['code']}：结果{it['result']}，参考{it['lo']}~{it['hi']}，"
                f"程序判定为【{labels[it['status']]}】"
            )
    return "\n".join(rows)

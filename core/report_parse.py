# 体检指标解析与判定：从 OCR 逐行文本里提取 代号/结果/参考范围，用代码精确判断
# 正常/偏高/偏低，不依赖 LLM 做数值比较（LLM 对范围内数值容易误报）。
#
# 【10.21 增强】在原有 范围解析 + unparsed 兜底 基础上补齐：
#   1) 单位解析：每条指标输出 unit（mmol/L、mg/dL、U/L、10^9/L、mmHg 等）
#   2) 表格行列处理：跳过表头行；把“只有指标名/代号、无数字”的折行与后续数值行合并
#   3) OCR 原文证据字段：每条指标带 ocr_text（来源行原文）、source_line（行号）、
#      range_text（识别的范围原文），供前端展示“原文证据”
#   4) 二次规则校验：生理学合理值范围，明显超出生理范围的数值判为 OCR 小数点/单位错值，
#      降级为 unparsed（保留证据，不当作异常交给 LLM）
# 保持向后兼容：原 code/result/lo/hi/status 判定结果不变，新增字段供前端可选展示。
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

# 【增强1】常见测量单位（体检单）：优先匹配 10^9/L 类，再匹配 数值/单位，最后独立单位
# (?<!\d) 防止把结果数字（如 5.8 中的 8）误并入 "10^9/L"
_UNIT = re.compile(
    r"(?<!\d)(?:[×x]\s*)?10\s*[\^eE]?\s*[+-]?\s*\d+\s*/\s*[A-Za-z%]+"
    r"|(?:mmol|[µμ]?mol|umol|mg|ng|pg|[µμ]?g|ug|g|U|IU)\s*/\s*(?:dL|dl|L|l|mL|ml|HPF|hpf)"
    r"|mm\s*Hg|mmHg|mm/Hg"
    r"|[fF][lL]|[pP][gG]|[gG]\s*/\s*[lL]|%"
)

# 【增强2】表头行特征词：行内含这些词且无数字时判定为表头，跳过不解析
_HEADER_WORDS = ("参考范围", "正常范围", "参考值", "结果", "单位",
                 "项目", "检查项目", "测定项目", "指标")

# 【增强4】二次校验：生理学合理值范围（宽松，只拦明显 OCR 小数点/单位错值）
_PLAUSIBLE = {
    "GLU": (0.5, 40), "血糖": (0.5, 40), "空腹血糖": (0.5, 40),
    "TC": (0.5, 20), "总胆固醇": (0.5, 20),
    "TG": (0.2, 30), "甘油三酯": (0.2, 30),
    "HDL": (0.1, 5), "LDL": (0.1, 10),
    "高密度脂蛋白": (0.1, 5), "低密度脂蛋白": (0.1, 10),
    "ALT": (1, 600), "AST": (1, 600),
    "谷丙转氨酶": (1, 600), "谷草转氨酶": (1, 600),
    "Hb": (30, 300), "血红蛋白": (30, 300),
    "WBC": (0.1, 200), "白细胞": (0.1, 200),
    "肌酐": (10, 1500), "尿酸": (50, 1000), "尿素": (0.5, 40),
    "血压": (30, 300), "收缩压": (60, 260), "舒张压": (30, 160),
}


def _to_num(s: str) -> float:
    """把 OCR 数字字符串转 float，兼容空格、逗号小数点。"""
    s = s.replace(" ", "").replace(",", ".")
    return float(s)


def _strip_units(text: str) -> str:
    """移除文本中含数字的单位表达式，防止单位数字被误提取为结果。"""
    return _UNIT_WITH_NUM.sub(" ", text)


# 单位前的 OCR 噪声：↑↓ 箭头被识别成 ↑/↓/I/1，μmol/L 的 μ 可能被识别成 1。
# 这些符号不是结果值，统一剥离（只剥离"紧跟单位"的单个噪声字符，不误伤 10^9/L 类真数字单位）。
_UNIT_NOISE = re.compile(
    r"[↑↓↑↓Ii1](?=[µμ]?\s*mol\s*/\s*[lL]|[µμ]?\s*g\s*/\s*[lL]|"
    r"[mM]?\s*g\s*/\s*[lL]|U\s*/\s*[lL]|[fF][lL]|[pP][gG]|%$)"
)


def _normalize_unit_noise(line: str) -> str:
    """剥离单位前的 ↑↓/I/1 噪声并统一 μ 码位，避免它们被当成结果值或污染单位解析。"""
    line = _UNIT_NOISE.sub("", line)
    line = line.replace("\u00b5", "μ")
    return line


def _extract_result(line: str, range_start: int) -> float | None:
    """从范围之前的文本里取结果数字：去掉行首序号和单位中的数字后取最后一个数字。"""
    before = line[:range_start]
    # 去掉行首序号（如 "1 ALT 50" 里的 "1"），仅当序号后紧跟名称/代号（非数值/单位）。
    # 避免误删真正的首列结果值（如 "14.4 U/L 9.0-50.0" 的 14.4、"0.31 g/L ..." 的 0.31）。
    before = re.sub(r"^\d{1,2}\s+(?=[A-Z]{2,}|[\u4e00-\u9fff])", "", before)
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


def _extract_unit(line: str) -> str | None:
    """【增强1】提取该行出现的测量单位；未识别返回 None。"""
    m = _UNIT.search(line)
    return m.group(0) if m else None


def _is_header(line: str) -> bool:
    """【增强2】表头行判定：含表头特征词且行内无数字（真实指标数据行一般带数字）。"""
    return any(w in line for w in _HEADER_WORDS) and not re.search(r"\d", line)


def _merge_lines(raw_lines: list[str]) -> list[tuple[str, list[int], str]]:
    """【增强2】表格行列初版：
    - 跳过表头行；
    - 把“只有指标名/代号、无数字”的折行与后续数值行合并。
    返回 [(合并后行, 源行号列表, 合并前原文拼接)]，源行号列表覆盖参与合并的每一行，
    供证据字段返回完整原文，避免 OCR 拆行后只看到第一行。"""
    merged: list[tuple[str, list[int], str]] = []
    n = len(raw_lines)
    i = 0
    while i < n:
        line = raw_lines[i].strip()
        if not line:
            i += 1
            continue
        if _is_header(line):
            i += 1
            continue
        # 错行合并：有指标名/代号但本行无数字，且后续存在数值行 → 拼接
        if _extract_code(line) and not re.search(r"\d", line):
            buf_text = [line]
            buf_lines = [i]
            j = i + 1
            while j < n:
                nxt = raw_lines[j].strip()
                if not nxt:
                    j += 1
                    continue
                if _is_header(nxt):
                    break
                buf_text.append(nxt)
                buf_lines.append(j)
                if re.search(r"\d", nxt):
                    break
                j += 1
            merged.append((" ".join(buf_text), buf_lines, "\n".join(buf_text)))
            i = j + 1
            continue
        merged.append((line, [i], line))
        i += 1
    return merged


def _second_pass(metrics: list[dict]) -> list[dict]:
    """【增强4】二次规则校验：
    对已判定 high/low 的指标，若数值超出该指标生理学合理范围，判定为 OCR 小数点/单位错值，
    降级为 unparsed（保留证据，不当作异常交给 LLM）。不影响生理范围内的正常判定。"""
    out = []
    for m in metrics:
        code = (m.get("code") or "").upper()
        bounds = _PLAUSIBLE.get(code) or _PLAUSIBLE.get(m.get("code") or "")
        if (bounds and m["status"] in ("high", "low")
                and m.get("result") is not None
                and not (bounds[0] <= m["result"] <= bounds[1])):
            m["status"] = "unparsed"
        out.append(m)
    return out


def parse_metrics(ocr_text: str) -> list[dict]:
    """返回 [{code, result, lo, hi, status, unit, ocr_text, source_line, range_text}]。
    status ∈ normal/high/low/unparsed。
    unparsed 表示这一行有指标代号+数字但没识别出参考范围（或二次校验判定为 OCR 错值），
    不能当作正常。
    ocr_text/source_line/range_text 为 OCR 原文证据字段，供前端展示“原始证据”。"""
    raw_lines = ocr_text.split("\n")
    metrics = []
    for line, src_lines, merged_evidence in _merge_lines(raw_lines):
        line = _normalize_unit_noise(line.strip())
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
                # 范围行前无数字（如 "U/L 0.0-40.0"）：保留为孤儿范围行，
                # 后续与第一堆 unparsed 指标按顺序配对
                metrics.append({
                    "code": None, "result": None,
                    "lo": lo, "hi": hi, "status": "unparsed",
                    "unit": _extract_unit(line),
                    "ocr_text": merged_evidence,
                    "source_line": src_lines[0],
                    "source_lines": src_lines,
                    "range_text": m.group(0),
                })
                continue
            if result < lo:
                status = "low"
            elif result > hi:
                status = "high"
            else:
                status = "normal"
            metrics.append({
                "code": code, "result": result,
                "lo": lo, "hi": hi, "status": status,
                "unit": _extract_unit(line),
                "ocr_text": merged_evidence,
                "source_line": src_lines[0],
                "source_lines": src_lines,
                "range_text": m.group(0),
            })
        else:
            # 没匹配到范围，但行里有名称/代号+数字 → 标记为未能核对
            code = _extract_code(line)
            if code and re.search(r"\d", line):
                metrics.append({
                    "code": code, "result": _extract_unparsed_result(line, code),
                    "lo": None, "hi": None, "status": "unparsed",
                    "unit": _extract_unit(line),
                    "ocr_text": merged_evidence,
                    "source_line": src_lines[0],
                    "source_lines": src_lines,
                    "range_text": None,
                })

    metrics = _second_pass(metrics)

    # 【增强5】保守处理拆堆 OCR：只有恰好一个待核对指标和一个孤立范围，
    # 且单位明确兼容时才配对。多项/错序等情形无法证明对应关系，必须保留 unparsed。
    pending_ranges = [m for m in metrics
                      if not m.get("code") and m.get("lo") is not None]
    if pending_ranges:
        unparsed = [m for m in metrics if m["status"] == "unparsed" and m.get("result") is not None]
        result_metrics = [m for m in metrics if m.get("result") is not None]
        def unit_key(value):
            return re.sub(r"\s+", "", (value or "")).lower()

        left_unit = unit_key(unparsed[0].get("unit")) if len(unparsed) == 1 else ""
        right_unit = unit_key(pending_ranges[0].get("unit")) if len(pending_ranges) == 1 else ""
        can_pair = (len(unparsed) == 1 and len(result_metrics) == 1
                    and len(pending_ranges) == 1
                    and bool(left_unit) and left_unit == right_unit)
        if can_pair:
            um, rm = unparsed[0], pending_ranges[0]
            um["lo"], um["hi"] = rm["lo"], rm["hi"]
            um["range_text"] = rm.get("range_text")
            um["ocr_text"] = (um.get("ocr_text", "") + "\n" + rm.get("ocr_text", "")).strip()
            um["source_lines"] = sorted(set(um.get("source_lines", []) + rm.get("source_lines", [])))
            um["verification_reason"] = "唯一待核对指标与孤立范围数量匹配且单位相同"
            r = um["result"]
            um["status"] = "low" if r < rm["lo"] else ("high" if r > rm["hi"] else "normal")
            metrics.remove(rm)

    # 配对后再次校验；多栏挤在同一行或范围/单位有歧义时保留证据，不强作结论。
    metrics = _second_pass(metrics)
    for item in metrics:
        item["parser_version"] = "2.2.0"
        reason = None
        if len(_RANGE.findall(item.get("ocr_text") or "")) > 1:
            reason = "同一 OCR 证据行包含多个参考范围，指标对应关系不明确"
        elif item.get("lo") is not None and item.get("hi") is not None and item["lo"] > item["hi"]:
            reason = "参考范围上下限顺序异常，需人工核对"
        elif item.get("result") is not None and not item.get("unit"):
            reason = "未识别到计量单位，需人工核对"
        if reason:
            item["status"] = "unparsed"
            item["verification_reason"] = reason
        bp_pair = re.search(r"\b\d{2,3}\s*[/／]\s*\d{2,3}\b", item.get("ocr_text") or "")
        if item.get("code") in ("血压", "BP") and bp_pair:
            item.update(result=None, result_text=bp_pair.group(0), lo=None, hi=None,
                        status="unparsed", verification_reason="血压包含高低压两值，需分项人工核对")
        if item.get("verification_reason"):
            continue
        if item.get("status") == "unparsed":
            item["verification_reason"] = "未能可靠识别指标、单位或参考范围对应关系"
        elif item.get("status") in ("normal", "high", "low"):
            item["verification_reason"] = "同一 OCR 行识别到结果值及参考范围"
        else:
            item["verification_reason"] = "缺少足够证据完成核对"
    return metrics


def format_metrics(metrics: list[dict]) -> str:
    """把判定结果整理成给 LLM 的"已核对事实"文本。"""
    labels = {"normal": "正常", "high": "偏高", "low": "偏低", "unparsed": "未能核对"}
    rows = []
    for it in metrics:
        unit = f" {it['unit']}" if it.get("unit") else ""
        if it["status"] == "unparsed":
            result = it.get('result_text') or it.get('result')
            rows.append(f"{it['code']}：结果{result}{unit}，未能识别参考范围，程序判定为【未能核对】")
        else:
            rows.append(
                f"{it['code']}：结果{it['result']}{unit}，参考{it['lo']}~{it['hi']}，"
                f"程序判定为【{labels[it['status']]}】"
            )
    return "\n".join(rows)

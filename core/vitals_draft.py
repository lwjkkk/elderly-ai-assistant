# -*- coding: utf-8 -*-
"""语音转写文本 → 体征草稿对象（不落库）。

10.22 成员 A（后端）：从口述文本识别体征意图(bp/bs/hr/weight)与字段(对象/测量时间/数值/单位)，
只产出草稿对象，复用现有体征范围校验（范围与 api/vitals.py create_vital 完全一致），
确认后才由前端调 POST /api/vitals 落库；本模块不写数据库。

对外唯一入口：parse_spoken_vitals(text, hint_type=None, now=None) -> dict | None
"""
import re
from datetime import datetime, timedelta

VALID_TYPES = {"bp", "bs", "hr", "weight"}

# 各类型规范化单位
_UNIT = {"bp": "mmHg", "bs": "mmol/L", "hr": "次/分", "weight": "kg"}

# 范围校验（与 api/vitals.py create_vital 一致，勿改）
_RANGE = {
    "bp": {"sys": (30, 300), "dia": (20, 250)},   # 且收缩压必须 > 舒张压
    "bs": (1.0, 50.0),                             # mmol/L
    "hr": (30.0, 250.0),                           # 次/分
    "weight": (20.0, 300.0),                       # kg
}

# 类型→“对象”别名（用于意图识别/回显）
_TYPE_ALIAS = {
    "bp": ("血压", "高压", "低压", "收缩压", "舒张压"),
    "bs": ("血糖", "葡萄糖"),
    "hr": ("心率", "脉搏"),
    "weight": ("体重", "体质量"),
}

_CN_NUMERAL_CHARS = "零〇一二两三四五六七八九十百千"
_CN_DIGITS = {"零": 0, "〇": 0, "一": 1, "二": 2, "两": 2,
              "三": 3, "四": 4, "五": 5, "六": 6, "七": 7,
              "八": 8, "九": 9}
_CN_UNITS = {"十": 10, "百": 100, "千": 1000}

_TIME_SEG = [  # (时段词, 默认小时)
    ("凌晨", 3), ("早上", 7), ("早晨", 7), ("上午", 9), ("中午", 12),
    ("下午", 15), ("傍晚", 18), ("晚上", 19), ("晚间", 19), ("夜里", 22),
]


def _extract_time(text: str, now: datetime):
    """从口述文本提取测量时间。返回 (measured_text, measured_at_datetime或None)。
    相对时间基于 now 计算；没有显式时间时返回 (None, None)，由前端按默认当前时间处理。"""
    measured_text = None
    base_date = now.date()
    hour = None
    minute = None
    day_word = None

    for w in ("前天",):
        if w in text:
            base_date = now.date() - timedelta(days=2); day_word = w; measured_text = w; break
    if day_word is None:
        for w in ("昨天", "昨晚", "昨日"):
            if w in text:
                base_date = now.date() - timedelta(days=1); day_word = w; measured_text = w; break
    if day_word is None:
        for w in ("今天", "今早", "今晨"):
            if w in text:
                base_date = now.date(); day_word = w; measured_text = w; break

    seg_word = None
    for seg, h in _TIME_SEG:
        if seg in text:
            seg_word, hour = seg, h
            measured_text = f"{day_word or ''}{seg_word}".strip() if measured_text else seg_word
            break

    m_hour = re.search(r"(?:([01]?\d|2[0-3])\s*点|(?:凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|晚间|夜里)([01]?\d)\s*点?)", text)
    if m_hour:
        hour = int(m_hour.group(1) or m_hour.group(2))
        measured_text = f"{day_word or ''}{seg_word or ''}{hour}点".strip() if (day_word or seg_word) else f"{hour}点"
    m_min = re.search(r"([0-5]\d)\s*(?:分|半)?(?:[，。；,;]|$)", text)
    if m_min:
        minute = int(m_min.group(1))

    if measured_text is None:
        # 无任何时间词，给不出测量时间
        return None, None
    if hour is None:
        hour = now.hour
    if minute is None:
        minute = 0
    try:
        at = datetime(base_date.year, base_date.month, base_date.day, hour, minute)
    except ValueError:
        at = now
    return measured_text, at


def _parse_bp(text: str):
    # 优先“高压X低压Y/收缩压X舒张压Y”
    m = re.search(r"(?:高压|收缩压)[^\d]{0,6}(\d{2,3})[^，。；,;]{0,8}(?:低压|舒张压)[^\d]{0,6}(\d{2,3})", text)
    if m:
        return int(m.group(1)), int(m.group(2))
    # 通用 x/y
    m = re.search(r"(?:血压[^\d]{0,4})?(\d{2,3})\s*(?:/|／|比|分之)\s*(\d{2,3})", text)
    if m:
        return int(m.group(1)), int(m.group(2))

    number_chars = rf"0-9{_CN_NUMERAL_CHARS}"
    # 明确高压/低压标签下的中文数字或阿拉伯数字。
    m = re.search(
        rf"(?:高压|收缩压)[^0-9{_CN_NUMERAL_CHARS}]{{0,6}}([{number_chars}]{{1,8}})"
        rf".*?(?:低压|舒张压)[^0-9{_CN_NUMERAL_CHARS}]{{0,6}}([{number_chars}]{{1,8}})",
        text,
    )
    if m:
        pair = _parse_number_pair(m.group(1), m.group(2))
        if pair:
            return pair

    # 带“血压”上下文的分隔表达：血压一百四十五/九十、血压一百四十五，九十。
    pair_pattern = rf"(?:血压[^0-9{_CN_NUMERAL_CHARS}]{{0,4}})?([{number_chars}]{{1,8}})\s*(?:/|／|比|分之|，|,|和)\s*([{number_chars}]{{1,8}})"
    m = re.search(pair_pattern, text)
    if m:
        pair = _parse_number_pair(m.group(1), m.group(2))
        if pair:
            return pair

    # 常见语音转写会省略分隔符：“血压一百四十五九十”。
    m = re.search(rf"血压(?:是|为)?\s*([{_CN_NUMERAL_CHARS}0-9]{{4,12}})", text)
    if m:
        token = m.group(1)
        # 最长的有效收缩压前缀优先，剩余部分作为舒张压，避免把两值合并成一个数。
        for split in range(len(token) - 1, 0, -1):
            pair = _parse_number_pair(token[:split], token[split:])
            if pair:
                return pair
    return None


def _parse_chinese_integer(token: str) -> int | None:
    """解析中文整数（如“一四五”或“一百四十五”），不接受含糊的单位顺序。"""
    if not token:
        return None
    if all(ch in _CN_DIGITS for ch in token):
        return int("".join(str(_CN_DIGITS[ch]) for ch in token))

    total = 0
    number = 0
    last_unit = 10000
    previous_digit = False
    for ch in token:
        if ch in _CN_DIGITS:
            if previous_digit:
                return None
            number = _CN_DIGITS[ch]
            previous_digit = True
        elif ch in _CN_UNITS:
            unit = _CN_UNITS[ch]
            if unit >= last_unit:
                return None
            if number == 0:
                if unit != 10:
                    return None
                number = 1
            total += number * unit
            number = 0
            last_unit = unit
            previous_digit = False
        else:
            return None
    return total + number


def _parse_number(token: str) -> int | None:
    if token.isdigit():
        return int(token)
    if all(ch in _CN_NUMERAL_CHARS for ch in token):
        return _parse_chinese_integer(token)
    return None


def _parse_number_pair(first: str, second: str) -> tuple[int, int] | None:
    systolic, diastolic = _parse_number(first), _parse_number(second)
    if (systolic is None or diastolic is None or
            not (30 <= systolic <= 300 and 20 <= diastolic <= 250) or
            systolic <= diastolic):
        return None
    return systolic, diastolic


def _parse_bs(text: str):
    m = re.search(r"(?:血糖|葡萄糖)[^\d]{0,4}(\d+(?:\.\d+)?)\s*(mmol/l|mmol/L|mmoll|mg/dl|mg/dL|mgdl|毫摩尔每升|毫克每分升|毫摩尔/升|毫克/分升)?", text)
    if not m:
        return None
    val = float(m.group(1))
    unit = (m.group(2) or "").lower().replace(" ", "")
    if unit in ("mg/dl", "mgdl", "毫克每分升", "毫克/分升"):
        val = val / 18.0
        val = round(val, 2)
    return val


def extract_measurement_context(text: str) -> str | None:
    """从血糖口述中识别明确的测量场景；没有线索时返回 None。"""
    text = text or ""
    if "非空腹" in text:
        return "random"
    if any(word in text for word in ("空腹", "餐前", "饭前", "早餐前", "午餐前", "晚餐前")):
        return "fasting"
    if any(word in text for word in ("餐后", "饭后", "早餐后", "午餐后", "晚餐后")):
        return "postprandial"
    if any(word in text for word in ("随机", "随时测")):
        return "random"
    return None


def _parse_hr(text: str):
    m = re.search(r"(?:心率|脉搏)[^\d]{0,4}(\d{2,3})\s*(?:次/分|次每分钟|bpm|次|每分钟)?", text, re.IGNORECASE)
    if not m:
        return None
    return float(int(round(float(m.group(1)))))


def _parse_weight(text: str):
    m = re.search(r"(?:体重)[^\d]{0,4}(\d+(?:\.\d+)?)\s*(公斤|千克|kg|KG|斤)?", text)
    if not m:
        return None
    val = float(m.group(1))
    unit = (m.group(2) or "").strip()
    if unit in ("斤",):
        val = val / 2.0
        val = round(val, 1)
    return val


def validate_draft(d: dict) -> list[str]:
    """对草稿做范围校验（规则与 api/vitals.create_vital 一致）。返回错误列表；空表示通过。"""
    errors: list[str] = []
    t = d["type"]
    if t == "bp":
        sys, dia = d["systolic"], d["diastolic"]
        lo_s, hi_s = _RANGE["bp"]["sys"]
        lo_d, hi_d = _RANGE["bp"]["dia"]
        if sys is None or dia is None:
            errors.append("血压需同时有收缩压和舒张压")
            return errors
        if not (lo_s <= sys <= hi_s):
            errors.append(f"收缩压 {sys} 不在合理范围 {lo_s}~{hi_s} mmHg")
        if not (lo_d <= dia <= hi_d):
            errors.append(f"舒张压 {dia} 不在合理范围 {lo_d}~{hi_d} mmHg")
        if sys is not None and dia is not None and sys <= dia:
            errors.append("收缩压必须大于舒张压")
    else:
        val = d["value"]
        lo, hi = _RANGE[t]
        if val is None:
            errors.append("缺少数值")
            return errors
        if not (lo <= val <= hi):
            errors.append(f"{_UNIT[t]} 值 {val} 不在合理范围 {lo}~{hi}")
    return errors


def parse_spoken_vitals(text: str, hint_type: str | None = None, now: datetime | None = None) -> dict | None:
    """从口述文本解析体征草稿。命中体征口述时返回草稿 dict，否则返回 None。不落库。

    草稿字段：type/systolic/diastolic/value/unit/measured_text/measured_at/raw_text/
             confidence/valid/errors。
    """
    text = (text or "").strip()
    if not text:
        return None
    now = now or datetime.now()
    hint = (hint_type or "").lower()
    order = [hint] if hint in VALID_TYPES else list(VALID_TYPES)
    if hint not in VALID_TYPES and hint:
        order = list(VALID_TYPES)

    for t in order:
        raw_text = None
        values = None
        if t == "bp":
            pair = _parse_bp(text)
            if pair is not None:
                values = pair
                raw_text = _find_raw(text, pair)
        elif t == "bs":
            v = _parse_bs(text)
            if v is not None:
                values = v
                raw_text = _find_raw(text, (v,))
        elif t == "hr":
            v = _parse_hr(text)
            if v is not None:
                values = v
                raw_text = _find_raw(text, (v,))
        else:  # weight
            v = _parse_weight(text)
            if v is not None:
                values = v
                raw_text = _find_raw(text, (v,))
        if values is None:
            continue

        draft = {
            "type": t,
            "systolic": None,
            "diastolic": None,
            "value": None,
            "unit": _UNIT[t],
            "measured_text": None,
            "measured_at": None,
            "raw_text": raw_text or text,
            "measurement_context": extract_measurement_context(text) if t == "bs" else None,
            "confidence": 0.7,
            "valid": False,
            "errors": [],
        }
        if t == "bp":
            draft["systolic"], draft["diastolic"] = values
        else:
            draft["value"] = values
        m_text, m_at = _extract_time(text, now)
        draft["measured_text"] = m_text
        draft["measured_at"] = m_at.strftime("%Y-%m-%d %H:%M:%S") if m_at else None
        draft["errors"] = validate_draft(draft)
        draft["valid"] = len(draft["errors"]) == 0
        return draft
    return None


def _find_raw(text: str, values) -> str | None:
    """截取含数值/关键数字的原文片段，用于前端“原话证据”。"""
    for v in values:
        if v is None:
            continue
        pat = str(v).replace(".", r"\.?")
        m = re.search(r".{0,12}" + re.escape(str(v)) + r".{0,12}", text)
        if m:
            return m.group(0).strip()
    return None

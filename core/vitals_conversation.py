# -*- coding: utf-8 -*-
"""体征口述多轮会话：缺字段追问、字段合并、确认落库（未确认不写入）。10.23 成员A。

配合 core/vitals_draft 的草稿解析，本模块负责跨请求的会话状态机：
- 首轮口述不足时，记录缺失字段并生成追问；
- 后续口述补充字段并合并，仍缺则继续追问；
- 信息齐全(ready)后由接口 confirm 复用现有 POST /api/vitals 落库；
- status != confirmed 时一律不写 vitals 表（cancel/超时/重进页面均可恢复或作废）。

对外主入口：merge_turn(conv, text, hint_type=None, now=None) 就地合并并更新 conv 状态。
"""
import re
from datetime import datetime

from core.vitals_draft import (
    parse_spoken_vitals, validate_draft, extract_measurement_context,
    _UNIT, _TYPE_ALIAS,
)

VALID_TYPES = {"bp", "bs", "hr", "weight"}

_RANGE_HINT = {
    "bp": "收缩压 30~300 mmHg、舒张压 20~250 mmHg，且收缩压需大于舒张压",
    "bs": "1.0~50.0 mmol/L",
    "hr": "30~250 次/分",
    "weight": "20~300 kg",
}


def detect_type_word(text: str) -> str | None:
    """文本中是否出现某类体征类型词（用于缺 type 时定性）。"""
    for typ, aliases in _TYPE_ALIAS.items():
        for a in aliases:
            if a in (text or ""):
                return typ
    return None


def extract_single_bp(text: str):
    """从“高压/收缩压/低压/舒张压 + 数字”提取血压单值（第二轮只补一个值时用）。"""
    sys = dia = None
    m = re.search(r"(?:高压|收缩压)[^\d]{0,4}(\d{2,3})", text)
    if m:
        sys = int(m.group(1))
    m = re.search(r"(?:低压|舒张压)[^\d]{0,4}(\d{2,3})", text)
    if m:
        dia = int(m.group(1))
    return sys, dia


def extract_value(text: str) -> float | None:
    """从“纯数字 + 可选单位”的口述补充中取数值，按单位换算。"""
    m = re.search(r"(\d+(?:\.\d+)?)\s*(次/分|次|每分钟|mmol/l|mmol/L|mg/dl|mg/dL|毫克每分升|毫摩尔每升|公斤|千克|kg|斤)?", text)
    if not m:
        return None
    val = float(m.group(1))
    unit = (m.group(2) or "").strip()
    if unit in ("mg/dl", "mg/dL", "毫克每分升"):
        val = round(val / 18.0, 2)
    elif unit in ("斤",):
        val = round(val / 2.0, 1)
    return val


def compute_missing(conv) -> list[str]:
    """依据当前会话内容判定缺失字段。"""
    if not conv.type:
        return ["type"]
    if conv.type == "bp":
        m = []
        if conv.systolic is None:
            m.append("systolic")
        if conv.diastolic is None:
            m.append("diastolic")
        return m
    return ["value"] if conv.value is None else []


def build_question(conv, missing: list[str], errors: list[str]) -> str:
    if errors:
        return errors[0] + "，请确认或重新输入。"
    if not missing:
        return "信息已齐全，请确认保存。"
    if "type" in missing:
        return "您想记录哪一项体征？血压、血糖、心率还是体重？"
    if conv.type == "bp":
        if "systolic" in missing and "diastolic" in missing:
            return "血压需要收缩压和舒张压两个值，请告诉我，比如“140/90”或“高压150低压95”。"
        return "血压还差一个值，请再告诉我" + ("高压（收缩压）" if "systolic" in missing else "低压（舒张压）") + "是多少。"
    if "value" in missing:
        return f"还缺一个数值，请告诉我具体数字（参考范围：{_RANGE_HINT.get(conv.type, '')}）。"
    return "请补充缺失的信息。"


def _revalidate(conv) -> list[str]:
    d = {
        "type": conv.type,
        "systolic": conv.systolic,
        "diastolic": conv.diastolic,
        "value": conv.value,
        "unit": _UNIT.get(conv.type),
    }
    return validate_draft(d)


def merge_turn(conv, text: str, hint_type: str | None = None, now: datetime | None = None):
    """把新一轮口述文本合并进会话 conv（就地修改），并更新 missing/last_question/status。
    每一轮用户原话按顺序追加到 conv.raw_text，不被解析后的结构化字段覆盖，
    供老人和家属核对口述过程。"""
    now = now or datetime.now()
    text = (text or "").strip()

    # 0) 保留每轮原话：按换行追加累计原文，空轮次不写入
    if text:
        conv.raw_text = f"{conv.raw_text}\n{text}" if conv.raw_text else text

    # 1) 定性：会话还没有 type 时，优先从文本/hint 判断
    if conv.type is None:
        conv.type = detect_type_word(text) or ((hint_type or "").lower() if (hint_type or "").lower() in VALID_TYPES else None)

    # 测量场景可在任意一轮补充，例如回答追问时只说“空腹”。
    if conv.type == "bs":
        context = extract_measurement_context(text)
        if context:
            conv.measurement_context = context

    # 2) 用草稿解析器尽量拿结构化数值
    parsed = parse_spoken_vitals(text, hint_type=(conv.type or hint_type), now=now)

    # 3) 血压单值补充（“高压150”这种只补一个值）
    if conv.type == "bp":
        sys, dia = extract_single_bp(text)
        if sys is not None and conv.systolic is None:
            conv.systolic = sys
        if dia is not None and conv.diastolic is None:
            conv.diastolic = dia

    # 4) 采纳草稿解析出的字段（类型一致时）
    if parsed:
        if conv.type is None:
            conv.type = parsed["type"]
        if conv.type == parsed["type"]:
            if parsed.get("systolic") is not None:
                conv.systolic = parsed["systolic"]
            if parsed.get("diastolic") is not None:
                conv.diastolic = parsed["diastolic"]
            if parsed.get("value") is not None:
                conv.value = parsed["value"]
            if parsed.get("measurement_context"):
                conv.measurement_context = parsed["measurement_context"]
        if parsed.get("unit"):
            conv.unit = parsed["unit"]
        if parsed.get("measured_text"):
            conv.measured_text = parsed["measured_text"]
        if parsed.get("measured_at"):
            conv.measured_at = parsed["measured_at"]

    # 5) 非血压且仍缺数值：接受纯数字补充并换算
    if conv.type and conv.type != "bp" and conv.value is None:
        v = extract_value(text)
        if v is not None:
            conv.value = v

    conv.unit = conv.unit or _UNIT.get(conv.type)

    # 6) 重算缺失与范围，决定 status/question
    #    缺失字段优先于范围错误：数值还没齐时先追问缺失，避免把“缺一个值”误报成范围问题
    missing = compute_missing(conv)
    errors = _revalidate(conv) if conv.type else []
    if missing:
        conv.missing = missing
        conv.last_question = build_question(conv, missing, [])
        conv.status = "collecting"
    elif errors:
        conv.missing = []
        conv.last_question = build_question(conv, [], errors)
        conv.status = "collecting"
    else:
        conv.missing = []
        conv.last_question = "信息已齐全，请确认保存。"
        conv.status = "ready"
    return conv


def draft_payload(conv) -> dict:
    """把会话转成草稿 dict（供前端展示）。"""
    return {
        "type": conv.type,
        "systolic": conv.systolic,
        "diastolic": conv.diastolic,
        "value": conv.value,
        "measurement_context": conv.measurement_context or "unknown",
        "unit": conv.unit,
        "measured_text": conv.measured_text,
        "measured_at": conv.measured_at,
        "raw_text": conv.raw_text,
    }

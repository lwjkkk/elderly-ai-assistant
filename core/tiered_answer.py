# -*- coding: utf-8 -*-
"""
10.28 #12 健康回答三段式 + 老人简版/家属详版双角色输出。

三段式结构：① 结论（是什么）② 建议（怎么办）③ 就医提醒/注意事项。
- 家属详版：三段完整原文，含关注点/数值/复测/就医指征（面向需要掌握细节的家属）。
- 老人简版：每段压缩为一句要点，通俗、限长，并在就医提醒处保留兜底"请以医生意见为准"。

实现要点（避免 AI 幻觉、可追踪）：
- 结构化由 LLM 一次生成三段（带【结论】【建议】【就医提醒】标记），parse_three 容错解析；
  缺段不编造，补确定性兜底话术。
- 老人简版用确定性压缩（取每段首句、去术语、限长），不做第二次自由生成，保证可测可复现。
- 任一 LLM 调用失败 → 整体确定性降级（tiered_source="deterministic"），绝不假装 LLM 已输出。
"""
from __future__ import annotations

import re

from core.qwen_llm import call_qwen

# 三段标记
_TAG = re.compile(r"【(结论|建议|就医提醒)】")

# 紧急红旗症状：命中即强制前置"立即拨打120/急诊"提示，不与一般不适混为一谈。
# 依据常见急救分级：胸痛/胸闷压榨感、呼吸困难、意识不清、中风征象（口角歪斜/一侧无力/说话不清）、大出血。
_EMERGENCY_PATTERNS = [
    re.compile(r"胸痛|胸口压(榨|抑)|心口痛|胸口闷痛"),
    re.compile(r"呼吸困难|喘不上气|喘不过气|窒息感"),
    re.compile(r"意识(模糊|不清|丧失)|昏迷|叫不醒|突然晕倒"),
    re.compile(r"口角歪斜|嘴歪|一侧(肢体|手|脚)(麻木|无力|不能动)|说话(不清|含糊)|吐字不清"),
    re.compile(r"大?出血|呕血|咯血|便血|黑便"),
]
_EMERGENCY_SEEK_PREFIX = (
    "如出现胸痛胸闷、呼吸困难、意识不清、口角歪斜或一侧肢体无力等紧急情况，"
    "请立即拨打120或前往急诊，不要自行观察等待。"
)

_TIER_SYSTEM = (
    "你是面向老年人的健康知识回答助手，只做科普与风险提示，不做疾病诊断、不给处方。"
    "请把给定的回答整理成三段，每段用【结论】/【建议】/【就医提醒】开头，逐行输出："
    "【结论】先一句话说明是什么/当前情况；"
    "【建议】给出 1-3 条现在可以做的具体做法；"
    "【就医提醒】按紧急程度分级：紧急情况（胸痛胸闷、呼吸困难、意识不清、口角歪斜、一侧肢体无力、大出血）"
    "要明确写「立即拨打120或去急诊」，不要和一般头晕、乏力、轻度头痛混为一谈；"
    "一般不适写「建议尽快就诊或复诊」；异常读数写「先复测，仍异常请就诊」。"
    "语言通俗、句子要短、不夸大、不制造恐慌。只输出三段，不要其他内容。"
)

# 老人简版限长（字符）
ELDER_SIMPLE_MAX = {"conclusion": 40, "advice": 48, "seek": 80}
_FALLBACK_SEEK = "如有不适请及时就医，具体结果以医生意见为准。"


def _parts():
    return {"conclusion": "", "advice": "", "seek": ""}


def parse_three(raw: str) -> dict:
    """从 LLM 输出解析三段；缺段补确定性兜底，绝不编造内容。"""
    parts = _parts()
    if not raw:
        return {"conclusion": "请结合具体情况，建议与医生核对后再处理。",
                "advice": "建议结合自身情况并与医生沟通确认下一步做法。",
                "seek": _FALLBACK_SEEK}
    # 按标记切分：匹配到【X】处开始收集到下一个标记
    positions = [(m.start(), m.group(1)) for m in _TAG.finditer(raw)]
    for idx, (start, tag) in enumerate(positions):
        end = positions[idx + 1][0] if idx + 1 < len(positions) else len(raw)
        text = raw[start:end]
        seg = _TAG.sub("", text).strip()
        seg = seg.strip("：:") .strip()
        if tag == "结论":
            parts["conclusion"] = seg
        elif tag == "建议":
            parts["advice"] = seg
        elif tag == "就医提醒":
            parts["seek"] = seg
    if not parts["seek"]:
        parts["seek"] = _FALLBACK_SEEK
    if not parts["conclusion"]:
        parts["conclusion"] = "请结合具体情况，建议与医生核对后再处理。"
    if not parts["advice"]:
        parts["advice"] = "建议先观察并结合医生意见决定下一步，避免自行用药。"
    return parts


def _first_sentence(text: str, limit: int) -> str:
    """确定性压缩：取首句（按句号/分号截断），去常见引导词，限长。"""
    for sep in ("。", "；", "！", "？", "，", "\n"):
        cut = text.find(sep)
        if cut != -1:
            text = text[:cut]
            break
    text = re.sub(r"^根据|^首先|^建议|^结论[:：]?|^注意", "", text).strip()
    return text[:limit]


def elder_simple(parts: dict) -> dict:
    """老人简版：每段一句要点，通俗限长；就医提醒保留模型生成的具体内容，
    只在模型未给出时用兜底；紧急症状保留强制前缀。"""
    conclusion = _first_sentence(parts["conclusion"], ELDER_SIMPLE_MAX["conclusion"]) or parts["conclusion"][:ELDER_SIMPLE_MAX["conclusion"]]
    advice = _first_sentence(parts["advice"], ELDER_SIMPLE_MAX["advice"]) or parts["advice"][:ELDER_SIMPLE_MAX["advice"]]
    # 就医提醒：优先保留模型生成的具体内容（复查时机/就诊指征），不硬替换为通用兜底；
    # 仅当模型未给出 seek 时才用兜底。紧急症状保留强制前缀。
    raw_seek = (parts.get("seek") or "").strip()
    if not raw_seek:
        seek = _FALLBACK_SEEK
    elif raw_seek.startswith(_EMERGENCY_SEEK_PREFIX):
        # 紧急：保留强制前缀 + 模型后续补充的就诊说明，末尾加医生意见
        seek = raw_seek
        if len(seek) > ELDER_SIMPLE_MAX["seek"] + 40:
            seek = seek[:ELDER_SIMPLE_MAX["seek"] + 40] + "…"
    else:
        # 普通情况：截断到老人版长度，保留关键信息
        seek = raw_seek
        if len(seek) > ELDER_SIMPLE_MAX["seek"]:
            seek = seek[:ELDER_SIMPLE_MAX["seek"]].rstrip("，。；,;") + "。"
    return {
        "conclusion": conclusion,
        "advice": advice,
        "seek": seek,
        "note": "以上为系统提示，请以医生意见为准。",
    }


def family_detail(parts: dict) -> dict:
    """家属详版：三段完整原文 + 关注点提示。"""
    return {
        "conclusion": parts["conclusion"],
        "advice": parts["advice"],
        "seek": parts["seek"],
        "note": "关注点：请结合数值变化与医嘱，留意是否需要复查或就医。",
    }


def _has_emergency(text: str) -> bool:
    """检测文本中是否出现红旗紧急症状（胸痛/呼吸困难/意识异常/中风征象/大出血）。"""
    if not text:
        return False
    return any(p.search(text) for p in _EMERGENCY_PATTERNS)


def build(question: str, answer: str, role: str) -> dict:
    """生成三段式并按角色返回简版/详版。LLM 失败走确定性降级。
    若问题/回答中出现红旗紧急症状，就医提醒强制前置「立即拨打120/急诊」提示，
    不与一般不适混为一谈。"""
    try:
        raw = call_qwen(_TIER_SYSTEM, f"问题：{question}\n参考资料：{answer}")
        parts = parse_three(raw)
        source = "llm"
    except Exception:
        first = _first_sentence(answer, 60) or "请结合具体情况处理。"
        rest = answer.replace(first, "", 1).strip()
        parts = {
            "conclusion": first,
            "advice": rest[:200] if rest else "建议结合自身情况并与医生沟通确认下一步做法。",
            "seek": _FALLBACK_SEEK,
        }
        source = "deterministic"

    # 红旗症状分级：命中则在就医提醒最前面强制加紧急提示
    if _has_emergency(question) or _has_emergency(answer):
        if not parts["seek"].startswith(_EMERGENCY_SEEK_PREFIX):
            parts["seek"] = _EMERGENCY_SEEK_PREFIX + parts["seek"]

    if role == "family":
        view = family_detail(parts)
    else:
        view = elder_simple(parts)
    return {
        "source": source,
        "parts": parts,
        "view": view,
    }

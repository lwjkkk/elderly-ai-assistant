# -*- coding: utf-8 -*-
"""
10.28 #12 健康回答结构化输出 + 老人简版/家属详版双角色输出。

结构：① 关注点 ② 通俗解释 ③ 下一步 ④ 就医提醒。
- 家属详版：四段完整内容，保留关注点、解释、行动建议和就医指征。
- 老人简版：前三段确定性压缩，就医提醒保留急救条件和兜底。

实现要点（避免 AI 幻觉、可追踪）：
- 结构化由 LLM 一次生成四段（带【关注点】【是什么意思】【下一步】【就医提醒】标记）；
  缺段不编造，补确定性兜底话术。
- 老人简版用确定性压缩（取每段首句、去术语、限长），不做第二次自由生成，保证可测可复现。
- 任一 LLM 调用失败 → 整体确定性降级（tiered_source="deterministic"），绝不假装 LLM 已输出。
"""
from __future__ import annotations

import re

from core.qwen_llm import call_qwen

# 三段标记
_TAG = re.compile(r"【(关注点|是什么意思|下一步|结论|建议|就医提醒)】")

# 紧急红旗症状：命中即强制前置"立即拨打120/急诊"提示，不与一般不适混为一谈。
# 依据常见急救分级：胸痛/胸闷压榨感、呼吸困难、意识不清、中风征象（口角歪斜/一侧无力/说话不清）、大出血。
_EMERGENCY_PATTERNS = [
    re.compile(r"胸痛|胸闷|胸口发紧|胸部压迫|胸口压(榨|抑)|心口痛|胸口闷痛"),
    re.compile(r"呼吸困难|喘不上气|喘不过气|呼吸急促|窒息感"),
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
    "请根据用户问题及提供的参考资料直接回答，输出四段，每段用【关注点】/【是什么意思】/【下一步】/【就医提醒】开头，逐行输出："
    "【关注点】说明回答针对的现象或问题；"
    "【是什么意思】用通俗话解释现有证据能说明什么，并保留不确定性；"
    "【下一步】给出 1-3 条现在可以做的具体做法；"
    "【就医提醒】按紧急程度分级：紧急情况（胸痛胸闷、呼吸困难、意识不清、口角歪斜、一侧肢体无力、大出血）"
    "要明确写「立即拨打120或去急诊」，不要和一般头晕、乏力、轻度头痛混为一谈；"
    "一般不适写「建议尽快就诊或复诊」；异常读数写「先复测，仍异常请就诊」。"
    "语言通俗、句子要短、不夸大、不制造恐慌。只输出四段，不要其他内容。"
    "通常控制在200-350字，不重复同一建议，必须保留必要的风险条件和就医动作。"
)

# 老人简版限长（字符）
ELDER_SIMPLE_MAX = {"conclusion": 40, "advice": 48, "seek": 80}
_FALLBACK_SEEK = "如有不适请及时就医，具体结果以医生意见为准。"


def _parts():
    return {"concern": "", "meaning": "", "next_step": "", "seek": ""}


def parse_three(raw: str) -> dict:
    """从 LLM 输出解析四段；缺段补确定性兜底，绝不编造内容。"""
    parts = _parts()
    if not raw:
        return {"concern": "请结合具体情况核对当前问题。",
                "conclusion": "请结合具体情况核对当前问题。",
                "meaning": "现有信息不足以作出确定判断。",
                "next_step": "建议结合自身情况并与医生沟通确认下一步做法。",
                "advice": "建议结合自身情况并与医生沟通确认下一步做法。",
                "seek": _FALLBACK_SEEK}
    # 按标记切分：匹配到【X】处开始收集到下一个标记
    positions = [(m.start(), m.group(1)) for m in _TAG.finditer(raw)]
    for idx, (start, tag) in enumerate(positions):
        end = positions[idx + 1][0] if idx + 1 < len(positions) else len(raw)
        text = raw[start:end]
        seg = _TAG.sub("", text).strip()
        seg = seg.strip("：:") .strip()
        if tag in ("关注点", "结论"):
            parts["concern"] = seg
        elif tag == "是什么意思":
            parts["meaning"] = seg
        elif tag in ("下一步", "建议"):
            parts["next_step"] = seg
        elif tag == "就医提醒":
            parts["seek"] = seg
    if not parts["seek"]:
        parts["seek"] = _FALLBACK_SEEK
    if not parts["concern"]:
        parts["concern"] = "请结合具体情况核对当前问题。"
    if not parts["meaning"]:
        parts["meaning"] = "现有信息不足以作出确定判断，请勿据此自行诊断。"
    if not parts["next_step"]:
        parts["next_step"] = "建议先观察并结合医生意见决定下一步，避免自行用药。"
    return {**parts, "conclusion": parts["concern"], "advice": parts["next_step"]}


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
    concern = _first_sentence(parts["concern"], 40) or parts["concern"][:40]
    meaning = _first_sentence(parts["meaning"], 48) or parts["meaning"][:48]
    next_step = _first_sentence(parts["next_step"], 48) or parts["next_step"][:48]
    # 就医提醒：优先保留模型生成的具体内容（复查时机/就诊指征），不硬替换为通用兜底；
    # 仅当模型未给出 seek 时才用兜底。紧急症状保留强制前缀。
    raw_seek = (parts.get("seek") or "").strip()
    if not raw_seek:
        seek = _FALLBACK_SEEK
    else:
        # 就医条件与动作不可按字符截断，否则可能删掉“仍异常请就诊”等关键后半句。
        seek = raw_seek
    return {
        "concern": concern,
        "conclusion": concern,
        "meaning": meaning,
        "next_step": next_step,
        "advice": next_step,
        "seek": seek,
        "note": "以上为系统提示，请以医生意见为准。",
    }


def family_detail(parts: dict) -> dict:
    """家属详版：三段完整原文 + 关注点提示。"""
    return {
        "concern": parts["concern"],
        "conclusion": parts["concern"],
        "meaning": parts["meaning"],
        "next_step": parts["next_step"],
        "advice": parts["next_step"],
        "seek": parts["seek"],
        "note": "关注点：请结合数值变化与医嘱，留意是否需要复查或就医。",
    }


def _has_emergency(text: str) -> bool:
    """检测文本中是否出现红旗紧急症状（胸痛/呼吸困难/意识异常/中风征象/大出血）。"""
    if not text:
        return False
    return any(p.search(text) for p in _EMERGENCY_PATTERNS)


def build(question: str, answer: str, role: str, *, generated: bool = False) -> dict:
    """生成健康结构化回答并同时返回老人简版/家属详版。LLM 失败走确定性降级。
    若问题/回答中出现红旗紧急症状，就医提醒强制前置「立即拨打120/急诊」提示，
    不与一般不适混为一谈。"""
    try:
        # 主问答已经直接生成四段时，只做解析，绝不再请求一次模型。
        raw = answer if generated else call_qwen(_TIER_SYSTEM, f"问题：{question}\n参考资料：{answer}")
        if not raw or not _TAG.search(raw):
            raise ValueError("模型未返回结构化段落")
        parts = parse_three(raw)
        source = "llm"
    except Exception:
        first = _first_sentence(answer, 60) or "请结合具体情况处理。"
        rest = answer.replace(first, "", 1).strip()
        parts = {
            "concern": first,
            "meaning": "以下解释仅根据当前回答内容整理，信息不足时不能代替医生判断。",
            "next_step": rest[:200] if rest else "建议结合自身情况并与医生沟通确认下一步做法。",
            "seek": _FALLBACK_SEEK,
        }
        source = "deterministic"

    # 红旗症状分级：命中则在就医提醒最前面强制加紧急提示
    if _has_emergency(question) or _has_emergency(answer):
        if not parts["seek"].startswith(_EMERGENCY_SEEK_PREFIX):
            parts["seek"] = _EMERGENCY_SEEK_PREFIX + parts["seek"]

    elder_view = elder_simple(parts)
    family_view = family_detail(parts)
    view = family_view if role == "family" else elder_view
    # 保留旧版字段，兼容只读取结论/建议/就医提醒的客户端。
    legacy_parts = {
        **parts,
        "conclusion": parts["concern"],
        "advice": parts["next_step"],
    }
    return {
        "schema_version": 2,
        "source": source,
        "parts": legacy_parts,
        "elder_view": elder_view,
        "family_view": family_view,
        "view": view,
    }

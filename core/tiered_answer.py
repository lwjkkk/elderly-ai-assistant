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

# 四段标记，非健康场景使用补充提醒
_TAG = re.compile(r"【(关注点|是什么意思|下一步|结论|建议|就医提醒|补充提醒)】")

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


def parse_three(raw: str, module: str = 'health') -> dict:
    """从 LLM 输出解析四段；缺段补确定性兜底，绝不编造内容。"""
    parts = _parts()
    seek_fallback = _FALLBACK_SEEK if module == 'health' else '具体条件以官方说明或受理机构要求为准。'
    meaning_fallback = ('现有信息不足以作出确定判断，请勿据此自行诊断。' if module == 'health'
                        else '需要结合您的实际情况核对办理或操作条件。')
    action_fallback = ('建议先观察并结合医生意见决定下一步，避免自行用药。' if module == 'health'
                       else '请说明您使用的设备或办理所在地，以便核对下一步。')
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
        elif tag in ("就医提醒", "补充提醒"):
            parts["seek"] = seg
    if not parts["seek"]:
        parts["seek"] = seek_fallback
    if not parts["concern"]:
        parts["concern"] = "请结合具体情况核对当前问题。"
    if not parts["meaning"]:
        parts["meaning"] = meaning_fallback
    if not parts["next_step"]:
        parts["next_step"] = action_fallback
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
    next_step = parts["next_step"]  # Preserve all prohibitions and conditions in legacy safety replies.
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


def generation_prompt(module: str) -> str:
    domain = ('健康科普，解释证据与下一步，不诊断、不处方。就医提醒保留必要条件与动作。'
              if module == 'health' else
              '直接完成用户询问的操作或办理任务，不套用医疗问诊结构。医保问题讲资格、结算与办理流程，不转成药物剂量建议。')
    return (
        '你为同一个问题一次生成老人简版和家属详版。' + domain +
        '严格先输出【老人简版】，再输出【家属详版】。每组依次包含'
        '【关注点】【是什么意思】【下一步】以及' + ('【就医提醒】' if module == 'health' else '【补充提醒】') +
        '四项。老人简版总计约60至100字，用简单短句给出最少必要动作；家属详版约180至260字，'
        '补全参考资料内的条件、办理材料或核对事项，不复制简版凑数。两版事实一致，严禁虚构资料之外的细节。'
        '缺少参保地或险种时，先讲医院医保窗口核对、就诊开方和符合条件的直接结算流程，再追问；不保证本人符合报销资格。'
        '慢特病仅作为若符合当地资格时的可选办理分支，不写成所有高血压或糖尿病患者唯一或必需的报销途径。'
        '用户未提异地就医，不主动把备案当成必做步骤，不扩展无关流程。'
        '两版都保留关键禁忌和急救动作，不为缩短文字删掉否定条件。'
        '不输出思考过程、检索状态、通道、规则名、来源审核结论或重复免责声明，安全提醒只写一次必要内容。'
    )


def display_notice(module: str) -> str:
    from core.evidence import safety_notice
    return safety_notice(module)


def _decorate(view: dict, module: str) -> dict:
    labels = (('关注什么', '是什么意思', '下一步怎么办', '何时就医') if module == 'health'
              else ('办理事项', '适用条件', '办理步骤', '注意事项') if module == 'services'
              else ('要做什么', '准备条件', '操作步骤', '注意事项'))
    sections = [{'key': key, 'label': label, 'content': view.get(key, '').strip()}
                for key, label in zip(('concern', 'meaning', 'next_step', 'seek'), labels)
                if view.get(key, '').strip()]
    return {**view, 'conclusion': view.get('concern', ''),
            'advice': view.get('next_step', ''), 'note': '', 'sections': sections,
            'text': '\n\n'.join(section['label'] + '：\n' + section['content'] for section in sections)}


def build(question: str, answer: str, role: str, *, generated: bool = False, module: str = 'health') -> dict:
    """One generation, two explicit views; legacy answers remain parseable without another call."""
    raw = answer or ''
    source = 'llm'
    try:
        if not generated:
            raw = call_qwen(generation_prompt(module), f'问题：{question}\n参考资料：{answer}')
        raw = re.sub(r'<think>.*?</think>', '', raw, flags=re.S).strip()
        groups = re.search(r'【老人简版】(.*?)【家属详版】(.*)', raw, flags=re.S)
        if groups and all(_TAG.search(group) for group in groups.groups()):
            short_parts, parts = (parse_three(group, module=module) for group in groups.groups())
            elder_view, family_view = family_detail(short_parts), family_detail(parts)
        elif _TAG.search(raw):
            parts = parse_three(raw, module=module)
            elder_view, family_view = elder_simple(parts), family_detail(parts)
            # A short safety answer can legitimately share actions and warnings;
            # omit the longer explanation instead of inventing extra family facts.
            elder_view['meaning'] = ''
        else:
            source = 'deterministic'
            parts = {'concern': '请结合当前问题核对下一步。' if module == 'health' else '',
                     'meaning': '现有内容不足以作出诊断，请结合医生评估。' if module == 'health' else '',
                     'next_step': raw, 'seek': ''}
            if module == 'health':
                parts['seek'] = _FALLBACK_SEEK
            elder_view, family_view = dict(parts), dict(parts)
            if module != 'health' and len(raw) > 120:
                sentences = [s.strip() for s in re.split(r'(?<=[。！？])', raw) if s.strip()]
                if len(sentences) > 1:
                    elder_view['next_step'] = sentences[0] + sentences[-1]
    except Exception:
        source = 'deterministic'
        parts = {'concern': '请结合当前问题核对下一步。' if module == 'health' else '',
                 'meaning': '', 'next_step': answer or '暂时无法完成回答，请稍后重试。',
                 'seek': _FALLBACK_SEEK if module == 'health' else ''}
        elder_view, family_view = dict(parts), dict(parts)

    if module == 'health' and (_has_emergency(family_view.get('seek', '')) or '120' in family_view.get('seek', '')):
        elder_view['seek'] = family_view['seek']
    from core.query_policy import emergency_types
    if emergency_types(question):
        for view in (elder_view, family_view):
            seek = view.get('seek', '')
            if '120' not in seek:
                view['seek'] = '请立即拨打120，并按急救调度员指导处理。' + seek
    elder_view, family_view = _decorate(elder_view, module), _decorate(family_view, module)
    view = family_view if role == 'family' else elder_view
    return {'schema_version': 3, 'source': source,
            'parts': {**parts, 'conclusion': parts['concern'], 'advice': parts['next_step']},
            'elder_view': elder_view, 'family_view': family_view, 'view': view,
            'elder_answer': elder_view['text'], 'family_answer': family_view['text'],
            'views_distinct': elder_view['text'] != family_view['text'],
            'render_mode': 'dual_view', 'display_notice': display_notice(module)}

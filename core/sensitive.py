# 违禁词 / 不当内容扫描兜底
# 作用：在大模型回答返回给用户前做最后一道过滤——
# 1. 命中政治、暴恐、色情、赌博、毒品等高危词：整体替换为兜底话术；
# 2. 命中医疗绝对化/违规承诺词（根治、包治、无副作用等）：替换为谨慎表达，
#    避免给老人造成"这药一定能治好"的误导。

import re

# 高危违禁词（命中即拦截整段回答）
HIGH_RISK_WORDS = [
    # 政治敏感类（示意，可按比赛/平台要求补充）
    "颠覆国家", "分裂国家", "反动",
    # 暴恐类
    "制造炸弹", "自制枪支", "杀人方法", "恐怖袭击",
    # 色情类
    "色情", "裸体",
    # 赌博 / 毒品类
    "赌博网站", "毒品制作", "制毒",
]

# 医疗绝对化、违规承诺词 -> 谨慎替换
# 注意："不要自行停药"这类正确表述不能误伤，因此这里只处理"承诺性"词汇。
MEDICAL_ABSOLUTE = {
    "根治": "帮助改善",
    "彻底治愈": "帮助缓解",
    "完全治愈": "帮助缓解",
    "包治": "可能有助于",
    "药到病除": "用药后多可缓解",
    "百分之百": "通常",
    "百分百": "通常",
    "100%": "通常",
    "绝对安全": "按说明书使用一般较安全",
    "无任何副作用": "多数人可以耐受，但仍可能出现不适",
    "没有副作用": "多数人可以耐受，但仍可能出现不适",
    "祖传秘方": "传统说法",
    "灵丹妙药": "常用方法",
    "特效": "常用",
}

# 高危命中时的兜底回答
FALLBACK_REPLY = "抱歉，这个内容我没法提供。如果是健康问题，建议您咨询医生，情况紧急请拨打120。"


def scan(text: str) -> tuple[list[str], list[str]]:
    """返回 (命中的高危词, 命中的医疗绝对化词)。"""
    high = [w for w in HIGH_RISK_WORDS if w in text]
    med = [w for w in MEDICAL_ABSOLUTE if w in text]
    return high, med


def sanitize(text: str) -> tuple[str, bool]:
    """过滤文本，返回 (处理后的文本, 是否命中高危)。"""
    if not text:
        return text, False
    high, _ = scan(text)
    if high:
        return FALLBACK_REPLY, True

    cleaned = text
    for bad, good in MEDICAL_ABSOLUTE.items():
        cleaned = cleaned.replace(bad, good)
    # 合并替换后可能出现的重复标点/空格
    cleaned = re.sub(r"[，。]{2,}", "。", cleaned)
    return cleaned, False

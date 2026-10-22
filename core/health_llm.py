# 健康场景 LLM：症状自查（含风险分级）、体检报告建议
# 所有提示词都限定只做科普与风险提示，严禁疾病诊断、处方、调药。

import re

from core.qwen_llm import call_qwen

# 风险等级
RISK_GREEN = "green"    # 轻微，可先居家观察
RISK_YELLOW = "yellow"  # 需要警惕，建议尽快就医
RISK_RED = "red"        # 急症红旗，立即就医/拨打120

# 模型在结尾用这一行给出等级，便于程序解析
_RISK_PATTERN = re.compile(r"RISK[:：]\s*(green|yellow|red)", re.IGNORECASE)


SYMPTOM_SYSTEM_PROMPT = (
    "你是面向老年人的健康风险提示助手，只做风险判断和就医建议，不做疾病诊断。"
    "请根据老人描述的症状，用大白话说明：可能的方向、现在可以怎么做、什么情况下必须就医。"
    "并按以下标准判断风险等级："
    "green=症状轻微、常见，可先居家观察（如轻微鼻塞、偶尔咳嗽）；"
    "yellow=症状持续不缓解或需要警惕，建议尽快线下就医（如持续发热、反复头痛、明显乏力）；"
    "red=出现急症信号，必须立即就医或拨打120（如胸痛胸闷、呼吸困难、口角歪斜或说话不清、"
    "一侧肢体无力、意识模糊、突然剧烈头痛、大量出血、剧烈腹痛等）。"
    "语言要简短通俗、不制造恐慌，但遇到 red 信号必须明确、紧急地提示。"
    "严禁给出确定诊断、处方或具体用药。"
    "请在回答的最后另起一行，仅输出 RISK: green 或 RISK: yellow 或 RISK: red。"
)

REPORT_SYSTEM_PROMPT = (
    "你是面向老年人的体检报告解读助手，只做指标科普，不做疾病诊断。"
    "输入会先给你一份“程序已逐项核对的结果”，每项标注了【正常/偏高/偏低】，这是按结果数值和"
    "参考范围精确比较得出的事实。你必须严格照搬：严禁把正常项说成异常，严禁把偏高/偏低项说成正常，"
    "也不允许自行新增程序没有标出的异常项。"
    "你的任务是把这些结论用大白话讲出来：说明每个指标是查什么的；对偏高/偏低项解释意味着什么、"
    "是否需要复查或就医；正常项一句话带过即可。"
    "常见常识：HDL 高密度脂蛋白是“好胆固醇”，轻度偏高通常对心血管有保护作用、不必担心"
    "（即使程序按数值标为偏高，也要这样解释）；LDL 低密度脂蛋白是“坏胆固醇”，真正偏高才需警惕。"
    "输出结构：先列“需要关注的异常项”（只有程序确认没有偏高/偏低项时才能说没有已确认异常），"
    "再一句话带过正常项；存在未能核对项时必须单独列出，绝不能概括成“本次没有明显异常”或“一切正常”。"
    "最后给整体建议。句子要短、术语要解释、不夸大、不遗漏。"
    "严禁下疾病结论或给用药处方，结果以医生解读为准。"
)


def symptom_advice(input_text: str) -> tuple[str, str]:
    """根据症状描述返回 (建议文本, 风险等级)。无法判定时保守取 yellow。"""
    raw = call_qwen(SYMPTOM_SYSTEM_PROMPT, f"老人描述的症状：{input_text}")

    match = _RISK_PATTERN.search(raw)
    risk = match.group(1).lower() if match else RISK_YELLOW

    # 去掉结尾的 RISK 行，只保留给用户看的建议
    advice = _RISK_PATTERN.sub("", raw).strip()
    if not advice:
        advice = raw
    return advice, risk


def report_advice(ocr_text: str, metrics: list | None = None) -> str:
    """根据 OCR 文字与程序已核对的指标结论，返回大白话解读。
    异常项强制放在 prompt 最前，正常项另放，未解析项明确告知不能当正常。"""
    metrics = metrics or []
    labels = {"normal": "正常", "high": "偏高", "low": "偏低", "unparsed": "未能核对"}

    def _line(m):
        if m["status"] == "unparsed":
            result = m.get('result_text') or m.get('result')
            reason = m.get('verification_reason') or '参考范围未能识别'
            return f"{m['code']}：结果{result}，{reason}，判定【未能核对】"
        return (f"{m['code']} 结果{m['result']}，参考{m['lo']}~{m['hi']}，"
                f"判定【{labels[m['status']]}】")

    abnormal = [m for m in metrics if m["status"] in ("high", "low")]
    normal = [m for m in metrics if m["status"] == "normal"]
    unparsed = [m for m in metrics if m["status"] == "unparsed"]

    user = ""
    if abnormal:
        user += ("以下是程序已确认的异常项，你必须在回答最开头逐项列出并解释，"
                 "严禁写“没有明显异常”：\n"
                 + "\n".join(_line(m) for m in abnormal) + "\n\n")
    if normal:
        user += ("以下是程序确认的正常项，只需一句话带过：\n"
                 + "\n".join(_line(m) for m in normal) + "\n\n")
    if unparsed:
        user += ("以下指标未能自动核对参考范围（OCR 可能没识别清楚），"
                 "你不能把它们当作正常项一笔带过，必须明确提示老人：这些项需要对照纸质报告或请医生确认，"
                 "不要自行判断高低：\n"
                 + "\n".join(_line(m) for m in unparsed) + "\n\n")
    if not abnormal and not normal:
        user += ("注意：本次程序没有成功核对任何指标的参考范围，"
                 "你绝对不能回答“一切正常”或“均在正常范围内”，"
                 "必须如实说明“本次识别效果有限，未能自动核对各项指标，请对照纸质报告或请医生解读”。\n\n")
    user += "体检单原始识别文字：\n" + ocr_text

    answer = call_qwen(REPORT_SYSTEM_PROMPT, user)

    # 模型若给出与程序核对相冲突的整体正常结论，整段 AI 解读不可信，改为确定性提示。
    broad_normal_claim = re.search(
        r"(本次|报告|指标|结果)?\s*(没有明显异常|均在正常范围内|都在正常范围内|"
        r"一切正常|全部正常|未见异常)",
        answer,
    )
    if broad_normal_claim and (abnormal or unparsed or not metrics):
        answer = "AI 解读与程序核对结果不一致，已隐藏这段不可靠解读。请以报告原文及医生意见为准。"

    verified = []
    if abnormal:
        verified.append("程序核对的异常项：" + "；".join(_line(m) for m in abnormal))
    if unparsed:
        verified.append("未能核对项：" + "；".join(_line(m) for m in unparsed))
    if not metrics:
        verified.append("本次未能自动核对任何指标，不代表指标正常。")
    return ("程序核对结果：" + "\n".join(verified) + "\n\n" + answer) if verified else answer

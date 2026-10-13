# 对话摘要提取 + 落库
# 作用：POST /api/chat 回答后，判断是否属于需要同步给家属的 4 类业务
#       （drug 查药 / med 用药 / selfcheck 自查 / consult 咨询），
#       若是则调用 LLM 提炼一句话摘要，写入 chat_summaries 表。
# 原则：不属于 4 类或抽取失败时一律不落库，避免噪音记录。

import logging
import re

from db.database import SessionLocal
from db.models import ChatSummary, DrugQuery, User
from core.qwen_llm import call_qwen
from core.disclaimer import DRUG_DISCLAIMER

logger = logging.getLogger(__name__)

# 业务分类 → 判定关键词。命中才落库，其余模块（教程/办事/生活常识）不落库。
# 覆盖老人常见体征/慢病问法（血压/血糖/心率/胸闷等），避免健康对话漏判（BUG-009）
_CATEGORY_KEYWORDS = {
    "drug": ["查药", "药盒", "说明书", "这个药", "这个药是", "药的作用", "副作用", "禁忌",
             "药品", "药名", "什么药", "能一起吃", "药怎么吃", "吃药", "服", "药", "剂量",
             "说明书"],
    "med": ["用药", "吃药", "服药", "药提醒", "什么时候吃", "怎么吃", "忘吃", "漏吃",
            "吃几次", "饭前", "饭后", "一次吃", "停药", "换药", "降压药", "降糖药",
            "胰岛素", "药盒", "怎么吃"],
    "selfcheck": ["症状", "头疼", "头痛", "头晕", "发烧", "发热", "咳嗽", "感冒",
                  "哪里不舒服", "不舒服", "自查", "乏力", "胸闷", "恶心", "睡不着",
                  "血压", "血压高", "血压低", "血糖", "血糖高", "血糖低", "心率", "心跳",
                  "心慌", "心悸", "气短", "失眠", "拉肚子", "腹泻", "便秘", "关节",
                  "腰疼", "腿疼", "血压计", "血糖仪", "血脂", "尿酸", "转氨酶", "心悸"],
    "consult": ["咨询", "问诊", "挂号", "医院", "医生", "就诊", "看病", "预约",
                "住院", "复查", "门诊", "体检", "报告", "指标"],
}


def classify_category(question: str) -> str | None:
    """按关键词判定业务分类，不属于 4 类返回 None（不落库）。"""
    for cat, kws in _CATEGORY_KEYWORDS.items():
        if any(k in question for k in kws):
            return cat
    return None


# 摘要提示词：要求只输出固定格式，便于解析；无法提炼就输出 "NONE"
_SUMMARY_PROMPT = (
    "你是老年健康助手的记录员。根据用户的问题和助手回答，提炼一句简短、客观的"
    "【健康/就医相关记录】，用于同步给老人的家属查看。要求："
    "用大白话、一句话（不超过40字）、只陈述事实，不要出现「步骤一/第一步」等操作步骤。"
    "如果这段问答与健康、用药、查药、症状、就医完全无关，只输出：NONE\n"
    "否则只输出一行，格式：SUMMARY: <一句话记录>"
)


def _extract_summary(question: str, answer: str) -> str | None:
    """调用 LLM 提炼一句话摘要；失败或返回 NONE 则返回 None。"""
    try:
        user = (
            f"用户问题：{question}\n"
            f"助手回答：{answer[:800]}\n"
            f"请提炼记录："
        )
        raw = call_qwen(_SUMMARY_PROMPT, user).strip()
        m = re.search(r"SUMMARY[:：]\s*(.+)", raw, re.S)
        text = (m.group(1).strip() if m else raw.strip())
        if not text or text.upper().startswith("NONE") or text == "":
            return None
        text = text.strip()
        if len(text) > 80:
            text = text[:80]
        return text
    except Exception as e:
        logger.warning(f"摘要提炼失败：{e}")
        return None


def extract_risk(question: str, answer: str, category: str) -> str | None:
    """对 selfcheck 类，从回答里简单判定风险等级；失败返回 None 不落 risk。"""
    if category != "selfcheck":
        return None
    if any(k in answer for k in ("立即就医", "马上就医", "急诊", "尽快到医院", "立即去医院", "红色")):
        return "red"
    if any(k in answer for k in ("建议就医", "尽快就医", "去医院", "看医生", "门诊", "黄色")):
        return "yellow"
    return "green"


def save_summary_sync(elder_id: int, question: str, answer: str, module: str):
    """同步落库：判定分类→提炼摘要→写入 chat_summaries（独立 session，供后台线程用）。
    兜底：LLM 提炼失败时用问题截断作为记录，保证健康类对话不因模型不可用而丢失。"""
    category = classify_category(question)
    if not category:
        return False
    summary = _extract_summary(question, answer)
    if not summary:
        # 兜底：本地 LLM 未跑/提炼失败时，用问题本身截断作为摘要，
        # 确保家属端仍能看到这条健康/用药/症状对话记录（修复 BUG-009）
        summary = question.strip()
        if len(summary) > 80:
            summary = summary[:80] + "…"
    risk = extract_risk(question, answer, category)

    db = SessionLocal()
    try:
        db.add(ChatSummary(
            elder_id=elder_id,
            category=category,
            question=question.strip(),
            summary=summary,
            risk=risk,
            module=module or None,
            synced=False,
        ))
        # drug 类问答同时写一条 drug_queries（kind="chat"），
        # 让家属端查药卡片（/api/drugs/records）也能看到普通对话里的查药记录。
        if category == "drug":
            db.add(DrugQuery(
                elder_id=elder_id,
                kind="chat",
                input_text=question.strip(),
                ocr_text=question.strip(),
                explanation=(answer or "")[:500],
                disclaimer=DRUG_DISCLAIMER,
            ))
        db.commit()
        logger.info(f"对话摘要已落库 elder={elder_id} category={category} summary={summary}")
        return True
    except Exception as e:
        db.rollback()
        logger.warning(f"对话摘要落库失败：{e}")
        return False
    finally:
        db.close()

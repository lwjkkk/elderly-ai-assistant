# 核心智能体逻辑

import os
import re
import logging
import threading
from core.prompt import SYSTEM_PROMPT, MODULE_PROMPTS
from core.qwen_llm import call_qwen
from core.rag import retrieve_from_knowledge_base
from core import rag_hybrid, rag_indexer
from core.disclaimer import HEALTH_DISCLAIMER

logger = logging.getLogger(__name__)
_RAG_LOCK = threading.Lock()
_RAG_EMBEDDER = None

# 认"第X步"开头（X 为中文或阿拉伯数字）
_STEP_RE = re.compile(r"^第([一二三四五六七八九十0-9０-９]{1,3})步")
# 也认 "1. " "2、" "3)" 这类阿拉伯数字编号（本地模型常用这种格式）
_NUM_RE = re.compile(r"^\d{1,2}\s*[.、)]\s*")

# 知识库目录名 → 模块名的映射（RAG 命中时优先使用）
_DIR_TO_MODULE = {
    "phone_tutorial": "phone",
    "services": "services",
    "daily_life": "daily_life",
    "health": "health",
}


def _module_from_dir(dir_path: str) -> str:
    """根据知识库文件所在目录映射模块名，无法映射返回空字符串"""
    if not dir_path:
        return ""
    return _DIR_TO_MODULE.get(os.path.basename(dir_path), "")


def get_agent_answer(question: str) -> dict:
    """
    老年智能体主函数 - 前端调用这个接口

    入参：
        question: 用户的问题文字（含语音转文字后的文字）

    返回：
        {
            "answer": "完整回答",
            "module": "phone/services/daily_life/health",
            "steps": ["第一步...", "第二步..."],
            "disclaimer": "免责声明"
        }
    """
    try:
        # 检索用“问题文字”
        search_question = question

        # 1. 调用 RAG 检索知识库相关内容
        rag_results, rag_channel = _retrieve_references(search_question)
        rag_context = ""
        if rag_results:
            rag_context = "\n\n".join(
                _clean_reference(r["content"]) for r in rag_results
            )

        # 2. 拼接最终问题：RAG 有结果时以片段为依据；无结果时 AI 自由回答但守适老化/健康底线
        final_question = question
        if rag_context:
            final_question += (
                "\n\n以下是与用户问题直接相关的参考资料片段，只采用其中与用户问题直接相关的部分，"
                "无关内容一律忽略，更不要另起话题自行发挥；"
                "不要在回答正文中出现资料里的文件名、标题、关键词、分类、问题等原始信息；"
                "回答只依据下列参考片段，片段里没有提到的内容不要自行补充：\n"
                + rag_context
            )
        else:
            # 知识库未命中：不硬说"资料不足"，按通用常识回答，但要守适老化与健康安全底线
            final_question += (
                "\n\n知识库中没有检索到与该问题直接对应的参考资料。"
                "请你根据通用常识正常回答，但必须遵守：\n"
                "1. 适老化表达：像跟长辈说话，用大白话，不用专业术语；"
                "需要操作的问题按「第一步、第二步」分步骤，按钮名称用「」标出；"
                "2. 回答简短，只答用户问的那一点，不要扩展到没问到的话题；"
                "3. 涉及健康、用药、疾病、检查指标时，不要给出具体药物剂量、具体诊断、具体治疗方案，"
                "只能给一般性的生活建议，并提醒用户「具体情况请咨询医生或家里的年轻人」；"
                "4. 不要编造知识库中不存在的事实、数据、地址、电话。"
            )

        # 3. 确定模块：优先按 RAG 命中的知识库目录映射，否则按问题关键词判断
        module = _detect_module(search_question)
        if rag_results:
            dir_module = _module_from_dir(rag_results[0].get("dir", ""))
            # 明确健康问题不应因首条知识放在 daily_life 目录而降为生活问答，
            # 否则双视图健康结构与医疗免责声明会被跳过。
            if dir_module and module != "health":
                module = dir_module

        # 4. 生成回答（统一走文本模型）
        answer = call_qwen(
            system_prompt=SYSTEM_PROMPT,
            user_question=final_question,
        )

        # 5. 按适老化格式整理返回
        steps = _parse_steps(answer)

        return {
            "answer": answer,
            "module": module,
            "steps": steps,
            "sources": _source_payload(rag_results, rag_channel),
            "retrieval_channel": rag_channel,
            "evidence_status": "sufficient" if rag_results and rag_channel != "keyword_fallback" else ("insufficient" if rag_results else "none"),
            "fallback_reason": ("vector_index_unavailable" if rag_channel == "keyword_fallback"
                                else ("no_relevant_chunks" if not rag_results else None)),
            "index_version": rag_indexer.index_version() if hasattr(rag_indexer, "index_version") else None,
            "disclaimer": (HEALTH_DISCLAIMER if module == "health" else
                           "以上内容仅供参考，具体操作请以实际界面为准。如有疑问请咨询子女或社区工作人员。")
        }

    except ValueError as e:
        # API Key 配置问题
        logger.error(f"配置错误：{e}")
        return _error_response("系统配置异常，请联系管理员。")
    except TimeoutError as e:
        # 网络超时
        logger.error(f"请求超时：{e}")
        return _error_response("网络响应太慢了，请稍后再试一次。")
    except RuntimeError as e:
        # 其他运行时错误
        logger.error(f"调用异常：{e}")
        return _error_response("系统暂时出了点问题，请稍后再试。")
    except Exception as e:
        # 兜底异常处理
        logger.exception(f"未知错误：{e}")
        return _error_response("系统出了点状况，请稍后再试。")


def _retrieve_references(question: str) -> tuple[list[dict], str]:
    """优先使用本地向量+关键词混合检索；索引/模型不可用时回退旧关键词检索。"""
    global _RAG_EMBEDDER
    try:
        with _RAG_LOCK:
            if _RAG_EMBEDDER is None:
                _RAG_EMBEDDER = rag_indexer.build_embedder()
            embedder = _RAG_EMBEDDER
            db_path = rag_indexer.get_default_db_path()
            rag_hybrid.ensure_index(db_path=db_path, embedder=embedder)
        result = rag_hybrid.hybrid_retrieve(
            question, top_k=3, db_path=db_path, embedder=embedder
        )
        normalized = []
        for item in result.get("results", []):
            content = item.get("best_chunk") or ""
            if content.strip():
                normalized.append({
                    "content": content,
                    "source": item.get("source") or item.get("title") or "知识库",
                    "title": item.get("title") or item.get("source") or "知识库",
                    "channel": item.get("channel") or result.get("channel", "hybrid"),
                    # score = RRF 融合排序分（与排序顺序一致）；向量/关键词单通道分另列，避免前端混淆
                    "score": item.get("score"),
                    "vector_score": item.get("vector_score"),
                    "keyword_score": item.get("keyword_score"),
                    "dir": item.get("dir", ""),
                    "category": item.get("category", ""),
                    "document_id": item.get("document_id"),
                    "chunk_id": item.get("chunk_id"),
                    "chunk_index": item.get("chunk_index"),
                    "document_version": item.get("document_version"),
                    "source_url": item.get("source_url"),
                    "updated_at": item.get("updated_at"),
                    "region": item.get("region"),
                })
        return normalized, result.get("channel", "none")
    except Exception as e:
        logger.warning(f"混合 RAG 不可用，回退关键词检索：{e}")
        try:
            legacy = retrieve_from_knowledge_base(question, top_k=3)
            return [
                {
                    "content": item.get("content", ""),
                    "source": item.get("source") or "知识库",
                    "title": item.get("source") or "知识库",
                    "channel": "keyword_fallback",
                    "score": None,
                    "dir": item.get("dir", ""),
                    "category": "",
                    "document_id": None,
                    "chunk_id": None,
                    "chunk_index": None,
                    "document_version": None,
                    "source_url": None,
                    "updated_at": None,
                    "region": None,
                }
                for item in legacy if item.get("content")
            ], "keyword_fallback"
        except Exception as fallback_error:
            logger.warning(f"关键词 RAG 回退也失败：{fallback_error}")
            return [], "none"


def _source_payload(results: list[dict], channel: str) -> list[dict]:
    """仅返回实际注入模型上下文的来源片段，作为可核对的检索证据。
    score 为 RRF 融合排序分（与排序顺序一致）；vector_score/keyword_score 为单通道明细，
    前端不要把单通道分误当最终相关度。
    """
    return [
        {
            "source": item["source"],
            "title": item["title"],
            "excerpt": _clean_reference(item["content"])[:600],
            "channel": item.get("channel", channel),
            "score": item.get("score"),
            "vector_score": item.get("vector_score"),
            "keyword_score": item.get("keyword_score"),
            "category": item.get("category", ""),
            "document_id": item.get("document_id"),
            "chunk_id": item.get("chunk_id"),
            "chunk_index": item.get("chunk_index"),
            "document_version": item.get("document_version"),
            "source_url": item.get("source_url"),
            "updated_at": item.get("updated_at"),
            "region": item.get("region"),
        }
        for item in results if item.get("content")
    ]


# 知识库文件里的元信息行（检索资料给模型前需剔除，避免被照抄进回答）
_META_PREFIX = ("标题：", "标题:", "关键词：", "关键词:",
                "分类：", "分类:", "问题：", "问题:")


def _clean_reference(content: str) -> str:
    """
    清洗知识库文档：去掉标题/关键词/分类/问题等元信息，只保留“回答：”后的正文。

    知识库文件通常以 标题/关键词/分类/问题 开头，正文在“回答：”之后。
    若没有“回答：”标记，则逐行删除元信息行、保留其余正文。
    """
    lines = [l.strip() for l in content.splitlines() if l.strip()]

    # 找到“回答：”标记，只取它之后的内容
    for i, l in enumerate(lines):
        if l.startswith("回答：") or l.startswith("回答:"):
            head = l.split("：", 1)[-1].split(":", 1)[-1].strip()
            lines = ([head] if head else []) + lines[i + 1:]
            break

    out = [l for l in lines if not any(l.startswith(p) for p in _META_PREFIX)]
    return "\n".join(out).strip()


def _parse_steps(answer: str, max_steps: int = 6) -> list:
    """
    从模型回答中提取操作步骤。

    只认"第X步"开头的行（中文/阿拉伯数字均可），最多 max_steps 条，
    并按内容去重——避免把小模型回答里夹带的参考资料或幻觉文本算成步骤。
    如果没提取到任何步骤，把整个回答作为单步返回。
    """
    steps = []
    cur = None
    for raw in answer.strip().split("\n"):
        line = raw.strip()
        if not line:
            continue
        is_head = bool(_STEP_RE.match(line) or _NUM_RE.match(line))
        if is_head:
            # 遇到新编号，先收上一条
            if cur is not None:
                steps.append(cur)
            cur = line
            if len(steps) >= max_steps:
                break
        elif cur is not None:
            # 编号下的子项/说明，并入当前步骤，保证一步内容完整
            cur += "\n" + line
    if cur is not None and len(steps) < max_steps:
        steps.append(cur)

    # 按内容去重
    result = []
    for s in steps:
        if s not in result:
            result.append(s)
    # 两种编号都没匹配到，就把回答整体作为单步
    if not result:
        result = [answer]
    return result[:max_steps]


def _detect_module(question: str) -> str:
    """根据问题内容简单判断属于哪个模块（RAG 目录命中会覆盖此结果）"""
    from core.tiered_answer import _has_emergency
    if _has_emergency(question):
        return "health"
    phone_keywords = ["微信", "手机", "APP", "app", "软件", "怎么操作", "怎么打开", "怎么设置", "字体", "声音", "WiFi", "wifi", "蓝牙", "截屏", "拍照"]
    services_keywords = ["医保", "挂号", "社保", "公积金", "水电", "缴费", "养老金", "失业保险", "驾驶证", "年检", "退税", "报销", "备案"]
    health_keywords = ["血压", "血糖", "糖尿病", "高血压", "吃药", "用药", "药品", "症状", "头疼", "头痛",
                       "头晕", "发烧", "发热", "感冒", "咳嗽", "失眠", "睡眠", "饮食", "营养", "骨质疏松",
                       "锻炼", "健身", "心率", "胆固醇", "尿酸", "慢性病", "便秘", "牙疼", "肠胃", "健康"]

    for kw in phone_keywords:
        if kw in question:
            return "phone"
    for kw in services_keywords:
        if kw in question:
            return "services"
    for kw in health_keywords:
        if kw in question:
            return "health"
    return "daily_life"


def _error_response(tip: str) -> dict:
    """返回统一的错误格式"""
    return {
        "answer": tip,
        "module": "daily_life",
        "steps": [tip],
        "sources": [],
        "retrieval_channel": "none",
        "evidence_status": "none",
        "fallback_reason": "answer_generation_error",
        "index_version": None,
        "disclaimer": "以上内容仅供参考，具体操作请以实际界面为准。如有疑问请咨询子女或社区工作人员。"
    }

# RAG 基础检索 - 从知识库中检索与问题相关的片段

import os
import glob
import re
import logging

from config.settings import KNOWLEDGE_BASE_DIR

logger = logging.getLogger(__name__)

# 模块类别 → 知识库子目录名；新增 health 健康分支
CATEGORY_DIRS = {
    "phone": "phone_tutorial",
    "services": "services",
    "daily_life": "daily_life",
    "health": "health",
}

# 常见疑问词/辅助词，检索时先去掉，保留核心词
_STOP_WORDS = (
    "怎么", "如何", "怎样", "什么样", "什么", "怎么办", "怎么弄",
    "怎么操作", "教我", "帮我", "请问", "我想", "我要", "该怎样",
    "要怎样", "是不是", "有没有",
)


def _load_documents():
    """
    读取知识库目录下的所有 .txt / .md 文件，返回文档列表。

    自动递归扫描 KNOWLEDGE_BASE_DIR，C 同学把知识库文件放到
    knowledge_base 下的任意子目录都会被读到，不需要改这里的代码。

    返回：
        [{"content": "文档全文", "source": "文件名"}, ...]
    """
    docs = []
    if not os.path.isdir(KNOWLEDGE_BASE_DIR):
        logger.warning(f"知识库目录不存在：{KNOWLEDGE_BASE_DIR}")
        return docs

    for ext in ("*.txt", "*.md"):
        pattern = os.path.join(KNOWLEDGE_BASE_DIR, "**", ext)
        for path in glob.glob(pattern, recursive=True):
            try:
                # 中文文件可能是 UTF-8 或 GBK 编码，都尝试读取
                content = None
                for enc in ("utf-8", "gbk"):
                    try:
                        with open(path, encoding=enc) as f:
                            content = f.read().strip()
                        break
                    except UnicodeDecodeError:
                        continue
                if content:
                    # 记录文件相对 knowledge_base 的目录，便于按目录映射模块
                    rel_dir = os.path.relpath(os.path.dirname(path), KNOWLEDGE_BASE_DIR)
                    docs.append({
                        "content": content,
                        "source": os.path.basename(path),
                        "dir": "" if rel_dir == "." else rel_dir,
                    })
            except Exception as e:
                logger.warning(f"读取知识库文件失败 {path}: {e}")
    return docs


def _build_keywords(question: str) -> list:
    """
    把中文问题拆成可用作匹配的关键词。

    中文问题通常没有空格，直接整句匹配几乎必失败，所以：
    1. 按标点/空格切分；
    2. 去掉开头/结尾的疑问词（怎么、如何……），保留核心词；
    3. 用 2~3 字滑窗补充子串，确保"诈骗电话"这类核心短语能命中。
    """
    text = question.replace("？", " ").replace("?", " ").replace("，", " ").replace("。", " ")
    parts = [p.strip() for p in re.split(r"\s+", text) if p.strip()]

    keywords = []
    for part in parts:
        seg = part
        # 反复去掉开头疑问词，保留核心词
        changed = True
        while changed:
            changed = False
            for w in _STOP_WORDS:
                if seg.startswith(w):
                    seg = seg[len(w):]
                    changed = True
                    break
        if len(seg) >= 2:
            keywords.append(seg)
        # 滑窗补充 2~3 字片段
        if len(seg) >= 2:
            for n in (2, 3):
                for i in range(len(seg) - n + 1):
                    keywords.append(seg[i:i + n])

    # 去重，保持顺序
    seen = set()
    result = []
    for k in keywords:
        if k not in seen:
            seen.add(k)
            result.append(k)
    return result


def retrieve_from_knowledge_base(question: str, top_k: int = 2,
                                 category: str | None = None) -> list:
    """
    基础检索：从知识库中按关键词匹配，返回最相关的片段。

    参数：
        question: 用户的问题
        top_k: 返回最多几个片段
        category: 可选，限定只在某个类别目录检索
                  （phone/services/daily_life/health），不传则检索全部

    返回：
        [{"content": "相关片段全文", "source": "来源文件名"}, ...]
        没有匹配到时返回空列表。
    """
    keywords = _build_keywords(question)
    if not keywords:
        keywords = [question[:6]]

    only_dir = CATEGORY_DIRS.get(category or "", "")
    docs = _load_documents()
    scored = []
    for doc in docs:
        if only_dir and os.path.basename(doc["dir"]) != only_dir:
            continue
        total = sum(doc["content"].lower().count(k.lower()) for k in keywords)
        if total > 0:
            scored.append({
                "score": total,
                "content": doc["content"],
                "source": doc["source"],
                "dir": doc["dir"],
            })

    # 按匹配度从高到低排序，取前 top_k 个
    scored.sort(key=lambda x: x["score"], reverse=True)
    return [
        {"content": d["content"], "source": d["source"], "dir": d["dir"]}
        for d in scored[:top_k]
    ]

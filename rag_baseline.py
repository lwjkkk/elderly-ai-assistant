# -*- coding: utf-8 -*-
"""10.20 改造前 RAG 基线：现有关键词检索对固定问题的命中结果（#7 改造前对照）。"""
from core.rag import retrieve_from_knowledge_base

QUESTIONS = [
    "微信怎么发语音消息给别人？",
    "怎么用医保卡挂号？",
    "怎么识别诈骗电话？",
    "晚上睡不着觉有什么办法？",
    "高血压怎么管理？",
    "糖尿病饮食要注意什么？",
]

for q in QUESTIONS:
    res = retrieve_from_knowledge_base(q)
    print(f"Q: {q}")
    if not res:
        print("   命中：无（低于阈值 _MIN_SCORE=3.0）")
    for r in res:
        print(f"   命中：{r['source']}（dir={r['dir'] or '/'}）")
    print()
print("== 基线说明：现有关键词检索，返回全文、不返回引用来源、无向量/分块 ==")

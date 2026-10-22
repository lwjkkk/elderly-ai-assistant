# -*- coding: utf-8 -*-
"""
RAG chunk 级回归评测（固定问题集）。

跑法：
  python backend_validation/test_rag_chunks.py

指标：
  - relevant_ratio：top_k 中相关来源占比（must_have 命中）
  - error_ratio：    top_k 中错误来源占比（must_not 命中）
  - miss：          预期有来源但返回空
  - fp：            预期无来源但返回了 top_k（误报）
  - empty_ok：      预期无来源且确实空

阈值写死为 core.rag_hybrid 里的默认值；调阈值请改 core/rag_hybrid.py 后重跑。
"""
import os, sys, json, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
sys.path.insert(0, r"D:\AICcode\.test_deps\rag_eval")

from core import rag_hybrid as rh
from core import rag_indexer as ri

CASES = [
    # --- health：血压相关（重点回归用户报的问题） ---
    {"q": "高血压怎么控制",
     "must_have": ["高血压"], "must_not": ["血压计规范", "血糖仪", "记录方法"], "expect_hit": True},
    {"q": "血压高了吃什么药",
     "must_have": ["高血压", "降压"], "must_not": ["血压计规范", "血糖仪"], "expect_hit": True},
    {"q": "怎么测血压才最准确",
     "must_have": ["血压"], "must_not": ["微信", "医保", "诈骗"], "expect_hit": True},
    {"q": "血压计怎么校准保养",
     "must_have": ["血压计"], "must_not": ["微信", "医保", "糖尿病"], "expect_hit": True},
    {"q": "糖尿病饮食要注意什么",
     "must_have": ["糖尿病"], "must_not": ["血压计", "微信", "睡眠", "医保"], "expect_hit": True},
    {"q": "晚上睡不着觉怎么办",
     "must_have": ["睡眠", "失眠"], "must_not": ["血压", "微信", "医保", "糖尿病"], "expect_hit": True},
    {"q": "胸痛是不是心梗",
     "must_have": ["冠心", "心绞", "卒", "心肺"], "must_not": ["微信", "医保", "手机"], "expect_hit": True},
    # --- phone / services / daily_life ---
    {"q": "微信怎么发红包转账",
     "must_have": ["微信", "转账", "红包"], "must_not": ["血压", "医保", "睡眠"], "expect_hit": True},
    {"q": "医保报销流程是什么",
     "must_have": ["医保", "报销"], "must_not": ["血压", "微信", "睡眠"], "expect_hit": True},
    {"q": "怎么识别诈骗电话",
     "must_have": ["诈骗"], "must_not": ["血压", "微信", "医保"], "expect_hit": True},
    {"q": "12306怎么买火车票",
     "must_have": ["火车", "12306"], "must_not": ["血压", "微信", "医保"], "expect_hit": True},
    {"q": "今天武汉天气怎么样",
     "must_have": ["天气"], "must_not": [], "expect_hit": True},
    # --- 应判知识库依据不足 ---
    {"q": "明天适合去海边钓鱼吗",
     "must_have": [], "must_not": [], "expect_hit": False},
    {"q": "明天天气适合去海边钓鱼吗",
     "must_have": [], "must_not": [], "expect_hit": False},
    {"q": "给我讲个笑话",
     "must_have": [], "must_not": [], "expect_hit": False},
]


def main():
    emb = ri.build_embedder()
    temporary_index = tempfile.TemporaryDirectory(prefix="silver-rag-eval-")
    db = os.path.join(temporary_index.name, "vectors.db")
    rh.ensure_index(db, emb)

    stats = {"relevant": 0, "total": 0, "error": 0, "miss": 0, "fp": 0, "empty_ok": 0, "n": 0}
    for c in CASES:
        r = rh.hybrid_retrieve(c["q"], top_k=3, embedder=emb, db_path=db)
        results = r["results"]
        titles = [x["title"] or "" for x in results]
        stats["n"] += 1
        if c["expect_hit"]:
            if not results:
                stats["miss"] += 1
                print(f"[MISS] {c['q']}  预期有来源但返回空")
            else:
                for t in titles:
                    stats["total"] += 1
                    rel = any(mh in t for mh in c["must_have"])
                    err = any(mn in t for mn in c["must_not"])
                    stats["relevant"] += int(rel)
                    stats["error"] += int(err)
                    tag = "OK " if rel and not err else ("ERR" if err else "?? ")
                    print(f"[{tag}] {c['q']}  ->  {t}")
        else:
            if not results:
                stats["empty_ok"] += 1
                print(f"[EMPTY-OK] {c['q']}  正确判空")
            else:
                stats["fp"] += 1
                print(f"[FP] {c['q']}  预期空但返回了 {[t for t in titles]}")

    stats["relevant_ratio"] = round(stats["relevant"] / stats["total"], 3) if stats["total"] else 1.0
    stats["error_ratio"] = round(stats["error"] / stats["total"], 3) if stats["total"] else 0.0
    print("\n==== 汇总 ====")
    print(json.dumps(stats, ensure_ascii=False, indent=2))

    # 验收门槛
    ok = (stats["error_ratio"] <= 0.05 and stats["miss"] == 0 and stats["fp"] <= 1
          and stats["relevant_ratio"] >= 0.80)
    print("\n验收:", "PASS" if ok else "FAIL")
    temporary_index.cleanup()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

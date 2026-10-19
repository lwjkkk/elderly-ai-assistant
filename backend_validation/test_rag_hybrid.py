# -*- coding: utf-8 -*-
"""10.25 #7 RAG 升级——混合排序/阈值回退/索引重建 真实环境测试（D:\\python，模型 D:\\models）。"""
import os
import sys
import time
import shutil
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core import rag_hybrid as rh
from core import rag_indexer as ri
from core import rag as kw

PASS, FAIL = [], []
KB = ri.get_kb_dir()
DB = ri.get_default_db_path()


def ok(name, cond, detail=""):
    if cond:
        PASS.append(name); print(f"[PASS] {name}" + (f"  {detail}" if detail else ""))
    else:
        FAIL.append(name); print(f"[FAIL] {name}  {detail}")


def main():
    emb = ri.build_embedder()

    # 1. 索引指纹：首次 ensure 建立指纹（真实库此前无指纹，允许重建一次），随后幂等
    ei0 = rh.ensure_index(DB, emb)
    ei = rh.ensure_index(DB, emb)
    ok("ensure_index: 指纹建立后幂等不重建", ei["rebuilt"] is False and ei["reason"] == "index_up_to_date",
       f"rebuilt={ei['rebuilt']} reason={ei['reason']}")
    # 2. 强制重建
    ei2 = rh.rebuild_index(DB, emb)
    ok("rebuild_index: 强制重建", ei2["rebuilt"] is True and ei2["reason"] == "rebuilt",
       f"stats docs={ei2['stats']['docs']} chunks={ei2['stats']['chunks']}")

    # 3. 索引重建检测（临时 kb/库，避免污染真实库）
    tmp = tempfile.mkdtemp(prefix="kb_test_")
    tmpkb = os.path.join(tmp, "kb"); os.makedirs(tmpkb)
    sample = os.path.join(KB, "health", "家用电子血压计规范操作.txt")
    shutil.copy(sample, os.path.join(tmpkb, "血压计.txt"))
    tmpdb = os.path.join(tmp, "vec.db")
    fp0 = rh.compute_fingerprint(tmpkb)
    e1 = rh.ensure_index(tmpdb, emb, kb_dir=tmpkb)
    ok("指纹重建: 首次构建", e1["rebuilt"] is True, f"docs={e1['stats']['docs']} chunks={e1['stats']['chunks']}")
    e2 = rh.ensure_index(tmpdb, emb, kb_dir=tmpkb)
    ok("指纹重建: 未变不重建", e2["rebuilt"] is False, f"reason={e2['reason']}")
    # 修改文件 → 指纹变化 → 重建
    time.sleep(0.01)
    with open(os.path.join(tmpkb, "血压计.txt"), "a", encoding="utf-8") as f:
        f.write("\n新增：校准周期测试行。\n")
    fp1 = rh.compute_fingerprint(tmpkb)
    ok("指纹检测: 文件变更后指纹变化", fp0 != fp1, f"{fp0[:8]} != {fp1[:8]}")
    e3 = rh.ensure_index(tmpdb, emb, kb_dir=tmpkb)
    ok("指纹重建: 变更后自动重建", e3["rebuilt"] is True and e3["reason"] == "kb_changed",
       f"reason={e3['reason']}")
    shutil.rmtree(tmp, ignore_errors=True)

    # 4. 混合检索（真实库，top_k=2）
    hits = [
        ("怎么测血压才最准确", "血压计"),
        ("微信怎么发红包/转账", "转账"),
        ("医保报销流程", "报销"),
        ("12306 怎么买火车票", "火车票"),
    ]
    for q, expect in hits:
        r = rh.hybrid_retrieve(q, top_k=2, embedder=emb, db_path=DB)
        top = r["results"][0] if r["results"] else {}
        ok(f"混合检索: '{q}' 命中'{expect}'",
           r["channel"] in ("hybrid", "keyword") and any(
               expect in (x["title"] or "") or expect in (x["keywords"] or "") or expect in (x["best_chunk"] or "")
               for x in r["results"]),
           f"channel={r['channel']} top={top.get('title')} score={top.get('score')}")

    # 5. 阈值/无命中回退：明显无关问题应判空（chunk 级阈值卡掉弱相关 chunk）
    r_none = rh.hybrid_retrieve("今天晚上吃什么菜比较好呢", top_k=2, embedder=emb, db_path=DB)
    ok("无命中回退: 无关问题返回空(知识库依据不足)",
       r_none["channel"] == "none" and r_none["results"] == [],
       f"channel={r_none['channel']} n={len(r_none['results'])}")

    # 6. 旧版关键词检索仍可用（对照）
    old_res = kw.retrieve_from_knowledge_base("怎么测血压才最准确", top_k=2)
    ok("旧版关键词检索仍可用(对照)", len(old_res) > 0, " | ".join(r["source"] for r in old_res))

    print("\n==== RESULT ====")
    print(f"PASS={len(PASS)} FAIL={len(FAIL)}  (10.25 RAG 混合/回退/重建)")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()

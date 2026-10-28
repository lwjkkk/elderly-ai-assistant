# -*- coding: utf-8 -*-
"""10.24 #7 RAG 原型——真实环境测试（D:\\python 3.13.5，模型 D:\\models）。"""

# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
import os
import sys
import json
import glob
import sqlite3

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core import rag_indexer as ri

DB = str(_Path.cwd() / 'test_knowledge_vectors.db')
KB = ri.get_kb_dir()
PASS = []
FAIL = []


def ok(name, cond, detail=""):
    if cond:
        PASS.append(name)
        print(f"[PASS] {name}" + (f"  {detail}" if detail else ""))
    else:
        FAIL.append(name)
        print(f"[FAIL] {name}  {detail}")


def main():
    # 1. 建索引
    emb = ri.build_embedder()
    st = ri.build_index(KB, DB, emb)
    ok("建索引: docs>0", st["docs"] > 0, f"docs={st['docs']} chunks={st['chunks']} skipped={st['skipped']}")
    ok("知识库 93 篇全入库(≥93)", st["docs"] >= 93, f"docs={st['docs']}")
    ok("embedding 维数=512", st["dim"] == 512)
    n_chunks = st["chunks"]
    ok("分块>0", n_chunks > 0, f"chunks={n_chunks}")

    # 2. metadata 保留校验
    con = sqlite3.connect(DB)
    cur = con.cursor()
    row = cur.execute(
        "SELECT source,title,category,keywords,questions,chunk_index,dir FROM knowledge_chunks "
        "WHERE source=? ORDER BY chunk_index LIMIT 1", ("家用电子血压计规范操作.txt",)).fetchone()
    ok("血压计 metadata: 标题", row and row[1] == "家用电子血压计规范操作与误差排查", str(row))
    ok("血压计 metadata: 分类", row and row[2] == "health", str(row))
    ok("血压计 metadata: 关键词", row and "血压计" in row[3], str(row))
    ok("血压计 metadata: 问题", row and "测血压" in row[4], str(row))
    ok("血压计 metadata: 目录", row and row[6] == "health", str(row))
    # 统计：元数据列非空占比
    total = cur.execute("SELECT COUNT(*) FROM knowledge_chunks").fetchone()[0]
    no_title = cur.execute("SELECT COUNT(*) FROM knowledge_chunks WHERE title IS NULL OR title=''").fetchone()[0]
    no_cat = cur.execute("SELECT COUNT(*) FROM knowledge_chunks WHERE category IS NULL OR category=''").fetchone()[0]
    ok("metadata 完整: 标题非空", no_title == 0, f"empty={no_title}/{total}")
    ok("metadata 完整: 分类非空", no_cat == 0, f"empty={no_cat}/{total}")
    ok("向量 BLOB 长度=512*4", cur.execute(
        "SELECT COUNT(*) FROM knowledge_chunks WHERE length(embedding)=2048").fetchone()[0] == total)

    # 3. 可重复构建：重建一次，块数与内容一致（确定性）
    st2 = ri.build_index(KB, DB, emb)
    ok("索引可重复构建: docs 一致", st2["docs"] == st["docs"], f"{st2['docs']}/{st['docs']}")
    ok("索引可重复构建: chunks 一致", st2["chunks"] == n_chunks, f"{st2['chunks']}/{n_chunks}")

    # 4. 检索用例（向量 top1 应命中相关文档）
    cases = [
        ("怎么测血压才准", "血压计"),
        ("微信怎么发红包/转账", "转账"),
        ("12306 怎么买火车票", "火车票"),
        ("医保报销流程", "报销"),
    ]
    for q, expect in cases:
        res = ri.query_index(DB, q, emb, top_k=2)
        ok(f"检索: '{q}' 命中含'{expect}'", any(expect in r["text"] or expect in r["keywords"] or expect in r["title"] for r in res),
           " | ".join(f"{r['title']}:{r['score']}" for r in res))

    # 5. 旧版关键词检索仍可用（对照）
    from core import rag as old
    old_res = old.retrieve_from_knowledge_base("怎么测血压才最准确", top_k=2)
    ok("旧版关键词检索仍可用(对照)", len(old_res) > 0,
       " | ".join(r["source"] for r in old_res))

    print("\n==== RESULT ====")
    print(f"PASS={len(PASS)} FAIL={len(FAIL)}  (10.24 RAG 原型)")
    print(f"索引统计: docs={st['docs']} chunks={st['chunks']} skipped={st['skipped']} dim={st['dim']} db={DB}")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()

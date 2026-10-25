# -*- coding: utf-8 -*-
"""
10.25 #7 RAG 升级——混合检索；10.19 成员A 二次优化：chunk 级召回/排序/阈值。

历史问题（10.19 测试发现）：
  旧版 hybrid_retrieve 是「文档级」融合——
    - 向量通道取每篇文档最高分 chunk 代表整篇文档；
    - 关键词通道按整篇文档加权打分；
    - RRF 在文档级排名上融合。
  后果：一篇「高血压居家管理」文档里关于「降压药」的 chunk 向量分高，
  把整篇文档拉进候选；而「家用电子血压计规范操作」里「测前准备/校准保养」
  这种只是顺带讲血压的 chunk，靠「血压」2 字碎片在关键词通道拿基础分，
  也混进 top_k，最终展示的 best_chunk 与用户问题（如「高血压怎么控制」）
  并不直接相关。

本次改造（按成员A建议顺序）：
  1) chunk 级召回：向量通道直接返回 top chunks，不再聚合到文档级；
     关键词通道在 chunk 文本上打分，且只计 ≥3 字词，避免 2 字碎片虚高；
  2) chunk 级 RRF 融合：两个通道各自出 chunk 排名，RRF 在 chunk id 上融合；
  3) 相关性门槛：向量分 < VECTOR_CHUNK_THRESHOLD、关键词分 < KEYWORD_CHUNK_MIN
     的 chunk 不进候选池；再进行对象/任务约束与语义重排；
     无直接相关片段时不展示来源；
  4) 同 source 去重：每篇文档最多保留 MAX_CHUNKS_PER_SOURCE 个 chunk，
     避免一篇长文档霸榜；
  5) 无足够依据时 channel="none"，由调用方在回答里提示「知识库依据不足」。

对外接口保持兼容：
  ensure_index / rebuild_index / hybrid_retrieve
  hybrid_retrieve 返回结构里 results 项仍然带 source/title/category/keywords/
  questions/dir/best_chunk/score/keyword_score/vector_score/channel，
  只是 best_chunk 现在是真正命中的那个 chunk 文本，而非整篇文档开头。
"""
import os
import json
import hashlib
import glob
import re

import numpy as np

from core import rag as _kw
from core import rag_indexer as _ri
from core.query_policy import normalize, matches_scope, active_profiles, documented_review, reference_applicable, is_ios_question

INDEX_FORMAT_VERSION = "review-context-20261024-v3"

# ---------------- 默认配置（阈值由 backend_validation/test_rag_chunks.py 网格搜索标定） ----------------
# 0.50 为向量候选门槛；最终还需对象/任务约束及重排，不代表回答准确率。
VECTOR_CHUNK_THRESHOLD = 0.50
KEYWORD_CHUNK_MIN = 2.0         # 单 chunk 关键词分低于此值不进候选
RRF_K = 60.0
# 保留旧参数供显式覆盖时诊断；默认不再用 RRF 硬门槛删除强单通道命中。
# 旧的小样本网格结果不能代表当前知识库的整体质量。
FINAL_MIN_RRF = 0.030
MAX_CHUNKS_PER_SOURCE = 2       # 同一篇文档最多保留几个 chunk
CANDIDATE_POOL = 50             # 每通道取多少 chunk 参与融合
META_TABLE = "knowledge_index_meta"

# 关键词碎片过滤：body 计分只认长度 >= MIN_BODY_KEYWORD_LEN 的词，2 字碎片（如「血压」「怎么」）不计分
MIN_BODY_KEYWORD_LEN = 3


# ---------- 1. 索引重建（指纹检测，逻辑不变） ----------
def compute_fingerprint(kb_dir: str) -> str:
    files = sorted(glob.glob(os.path.join(kb_dir, "**", "*.txt"), recursive=True))
    files += sorted(glob.glob(os.path.join(kb_dir, "**", "*.md"), recursive=True))
    seen = set()
    files = [f for f in files if not (f in seen or seen.add(f))]
    entries = []
    for f in files:
        rel = os.path.relpath(f, kb_dir)
        with open(f, "rb") as stream:
            digest = hashlib.sha256(stream.read()).hexdigest()
        entries.append((rel, digest))
    blob = json.dumps([INDEX_FORMAT_VERSION, entries], ensure_ascii=False, sort_keys=True)
    return hashlib.sha1(blob.encode("utf-8")).hexdigest()


def _read_meta(con, key):
    row = con.execute(f"SELECT value FROM {META_TABLE} WHERE key=?", (key,)).fetchone()
    return row[0] if row else None


def _metadata_fields(raw: str | None) -> dict:
    try:
        return json.loads(raw or "{}")
    except (TypeError, ValueError):
        return {}


def _matches_query_focus(question: str, title: str, body: str) -> bool:
    """显式疾病/子主题必须在候选中落地，不能只凭文章总标题给无关段落加分。"""
    if not matches_scope(question, title, body):
        return False
    question = normalize(question)
    if any(p[0] in ('reimbursement', 'medical_admin') for p in active_profiles(question)):
        if not re.search(r'异地|外地|跨省|转诊|备案', question) and re.search(r'异地|备案', title or ''):
            return False
        if not re.search(r'凭证|激活|医保码|刷码|社保卡', question) and re.search(r'电子凭证|电子社保卡|激活', title or ''):
            return False
    if re.search(r'进口药|国产药|医保目录', question) and re.search(r'医保|报销|能报|可报', question):
        if not re.search(r'进口|目录', body or ''):
            return False
    if re.search(r'截屏|截图', question) and not re.search(r'保存|相册|相簿|删除|编辑|分享|在哪', question):
        if not re.search(r'同时|组合键|辅助触控', body or ''):
            return False
    combined = (title or "") + "\n" + (body or "")
    for query_pattern, candidate_pattern in (
        (r"高血压|降压", r"血压|降压"),
        (r"糖尿病|控糖", r"糖尿病|血糖|控糖"),
    ):
        if (not any(p[0] in ('reimbursement', 'medical_admin') for p in active_profiles(question))
                and re.search(query_pattern, question) and not re.search(candidate_pattern, combined)):
            return False
    if re.search(r"12306|火车票|高铁票|动车票", question):
        if not re.search(r"12306|火车|高铁|(?<!机)动车|铁路", combined):
            return False
    if (re.search(r"校准|校验", question) or ("保养" in question and re.search(r"血压计|血糖仪|仪器|设备", question))) and not re.search(r"校准|保养|校验|维修|校正", body or ""):
        return False
    # 特定疾病咨询不应把另一种疾病的专用饮食限制当作通用建议。
    if "糖尿病" in question and re.search(r"肾脏病|肾病|透析", title or "") and "糖尿病" not in (title or ""):
        return False
    dietary = re.search(r"饮食|食物|吃什么|吃饭|少盐|膳食", question)
    if dietary and not re.search(r"吃什么药|药怎么吃|药物", question):
        if not re.search(r"饮食|食物|膳食|盐|蔬菜|青菜|水果|主食|油脂|油腻", body or ""):
            return False
    if "红包" in question and "转账" not in question and "红包" not in combined:
        return False
    return True


def ensure_index(db_path=None, embedder=None, force=False, kb_dir=None) -> dict:
    db_path = db_path or _ri.get_default_db_path()
    kb = kb_dir or _ri.get_kb_dir()
    fingerprint = compute_fingerprint(kb)
    os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)

    con = _ri._conn(db_path)
    con.execute(f"CREATE TABLE IF NOT EXISTS {META_TABLE}(key TEXT PRIMARY KEY, value TEXT)")
    stored = _read_meta(con, "kb_fingerprint")
    con.close()

    if not force and stored == fingerprint:
        return {"rebuilt": False, "reason": "index_up_to_date", "stats": {"fingerprint": fingerprint[:12]}}

    if embedder is None:
        embedder = _ri.build_embedder()
    stats = _ri.build_index(kb, db_path, embedder)
    con = _ri._conn(db_path)
    con.execute(f"CREATE TABLE IF NOT EXISTS {META_TABLE}(key TEXT PRIMARY KEY, value TEXT)")
    con.execute(f"INSERT OR REPLACE INTO {META_TABLE}(key,value) VALUES('kb_fingerprint',?)", (fingerprint,))
    con.commit()
    con.close()
    reason = "rebuilt" if force or stored is None else "kb_changed"
    return {"rebuilt": True, "reason": reason, "stats": stats}


def rebuild_index(db_path=None, embedder=None) -> dict:
    return ensure_index(db_path, embedder, force=True)


# ---------- 2. chunk 级向量通道 ----------
def _vector_chunk_scores(db_path: str, question: str, embedder,
                         limit: int = CANDIDATE_POOL,
                         threshold: float = VECTOR_CHUNK_THRESHOLD) -> list:
    """返回 top chunks（不按 source 聚合），向量分 >= threshold。"""
    con = _ri._conn(db_path)
    qv = _ri.embed_texts(embedder, [question])[0].reshape(1, -1)
    cur = con.cursor()
    cur.execute(
        f"SELECT id,source,title,category,keywords,questions,chunk_index,text,dir,metadata_json,embedding "
        f"FROM {_ri.TABLE}"
    )
    rows = cur.fetchall()
    con.close()
    if not rows:
        return []
    mat = np.vstack([np.frombuffer(r[10], dtype=np.float32) for r in rows]).astype(np.float32)
    scores = (mat @ qv.T).ravel()
    out = []
    for row, sc in zip(rows, scores):
        s = float(sc)
        if s < threshold:
            continue
        if not _matches_query_focus(question, row[2], row[7]):
            continue
        meta = _metadata_fields(row[9])
        if not reference_applicable(meta, question):
            continue
        out.append({
            "id": row[0], "source": row[1], "title": row[2], "category": row[3],
            "keywords": row[4], "questions": row[5], "chunk_index": row[6],
            "text": row[7], "dir": row[8], "vector_score": s,
            **{key: meta.get(key) for key in ("document_id", "chunk_id", "document_version",
                                               "source_url", "updated_at", "region", "platform", "aliases", "review_status", "reviewed_by", "reviewed_at", "valid_until", "source_scope", "review_notes")},
        })
    out.sort(key=lambda x: -x["vector_score"])
    return out[:limit]


# ---------- 3. chunk 级关键词通道 ----------
def _iter_chunks(db_path: str) -> list:
    con = _ri._conn(db_path)
    cur = con.cursor()
    cur.execute(
        f"SELECT id,source,title,category,keywords,questions,chunk_index,text,dir,metadata_json FROM {_ri.TABLE}"
    )
    rows = cur.fetchall()
    con.close()
    return rows


def _score_chunk(chunk_text: str, meta: dict, keywords: list) -> float:
    """
    chunk 级关键词打分：
      - title / keywords metadata 命中：高权重（这是人工标注的主题信号）；
      - chunk body：只计长度 >= MIN_BODY_KEYWORD_LEN 的词，避免「血压」「怎么」
        这类 2 字碎片把「测前准备」「校准保养」这种顺带讲血压的 chunk 抬起来；
      - 疑问词 _STOP_WORDS 不计分。
    """
    kws = [k for k in keywords if k not in _kw._STOP_WORDS]
    title = (meta.get("title") or "").lower()
    kw_meta = (meta.get("keywords") or "").lower()
    body = chunk_text.lower()

    meta_score = 0.0
    for k in kws:
        kl = k.lower()
        # title 命中权重最高
        if kl in title:
            meta_score += 6.0
        elif kl in kw_meta:
            meta_score += 4.0

    body_score = 0.0
    for k in kws:
        if len(k) < MIN_BODY_KEYWORD_LEN:
            continue
        kl = k.lower()
        cnt = body.count(kl)
        if cnt:
            body_score += min(cnt, 3) * (len(k) / 3.0)

    return min(meta_score, 8.0) + min(body_score, 16.0)


def _grams(text):
    text = normalize(text).lower()
    text = re.sub(r"老年人|老人|手机|怎么|如何|什么|请问|注意|一般|平时|需要|[\W_]", "", text)
    return {text[i:i+2] for i in range(max(0, len(text)-1))}


def _question_similarity(question, raw_questions):
    try:
        questions = json.loads(raw_questions or '[]') if isinstance(raw_questions, str) else raw_questions
    except (TypeError, ValueError):
        questions = []
    query = _grams(question)
    if not query or not isinstance(questions, list): return 0.0
    return max((2 * len(query & _grams(q)) / max(1, len(query) + len(_grams(q)))
                for q in questions if isinstance(q,str)), default=0.0)


def _keyword_chunk_scores(question: str, db_path: str,
                         limit: int = CANDIDATE_POOL,
                         min_score: float = KEYWORD_CHUNK_MIN) -> list:
    """在 db 里所有 chunk 上打分，返回 top chunks。"""
    kws = _kw._build_keywords(question) or [question[:6]]
    rows = _iter_chunks(db_path)
    out = []
    for rid, source, title, category, keywords, questions, cidx, text, dr, raw_meta in rows:
        if not _matches_query_focus(question, title, text):
            continue
        extra = _metadata_fields(raw_meta)
        if not reference_applicable(extra, question):
            continue
        meta = {"source": source, "title": title, "keywords": keywords,
                "category": category, "questions": questions, "dir": dr}
        s = _score_chunk(text, meta, kws)
        if s < min_score:
            continue
        out.append({
            "id": rid, "source": source, "title": title, "category": category,
            "keywords": keywords, "questions": questions, "chunk_index": cidx,
            "text": text, "dir": dr, "keyword_score": s,
            **{key: extra.get(key) for key in ("document_id", "chunk_id", "document_version",
                                                "source_url", "updated_at", "region", "platform", "aliases", "review_status", "reviewed_by", "reviewed_at", "valid_until", "source_scope", "review_notes")},
        })
    out.sort(key=lambda x: -x["keyword_score"])
    return out[:limit]


# ---------- 4. chunk 级 RRF 融合 ----------
def hybrid_retrieve(question: str, top_k: int = 3,
                    db_path: str = None, embedder=None,
                    vector_threshold: float = VECTOR_CHUNK_THRESHOLD,
                    keyword_min: float = KEYWORD_CHUNK_MIN,
                    final_min_rrf: float = FINAL_MIN_RRF,
                    max_per_source: int = MAX_CHUNKS_PER_SOURCE,
                    weights: tuple = (1.0, 1.0)) -> dict:
    """
    chunk 级混合检索：
      1) 向量通道：top chunks（>= vector_threshold）；
      2) 关键词通道：top chunks（>= keyword_min）；
      3) RRF 融合（chunk id 级别）；
      4) 对象/任务约束与语义重排（显式覆盖旧参数时保留 RRF 诊断门槛）；
      5) 同 source 最多保留 max_per_source 个 chunk；
      6) 无有效结果 → channel="none"，由调用方提示知识库依据不足。
    """
    question = normalize(question)
    db_path = db_path or _ri.get_default_db_path()
    if embedder is None:
        embedder = _ri.build_embedder()

    vec_chunks = _vector_chunk_scores(db_path, question, embedder,
                                      threshold=vector_threshold)
    kw_chunks = _keyword_chunk_scores(question, db_path, min_score=keyword_min)

    # 无任一通道命中 → 空
    if not vec_chunks and not kw_chunks:
        return {"channel": "none", "threshold": vector_threshold,
                "results": [], "reason": "no_candidate"}

    rank_vec = {c["id"]: i for i, c in enumerate(vec_chunks)}
    rank_kw = {c["id"]: i for i, c in enumerate(kw_chunks)}
    by_id = {}
    for c in vec_chunks:
        by_id[c["id"]] = c
    for c in kw_chunks:
        by_id.setdefault(c["id"], c).update(c)

    w_kw, w_vec = weights
    merged = []
    for cid in set(rank_vec) | set(rank_kw):
        rrf = 0.0
        if cid in rank_kw:
            rrf += w_kw / (RRF_K + rank_kw[cid])
        if cid in rank_vec:
            rrf += w_vec / (RRF_K + rank_vec[cid])
        merged.append((cid, rrf))
    # RRF用于候选融合，不再把单通道强命中按0.030硬删。
    # 实际排序联合语义分、问题示例及正文覆盖；实体/任务约束已在召回前执行。
    reranked=[]
    query_grams=_grams(question)
    for cid,rrf in merged:
        c=by_id[cid]
        text=c.get('text') or ''
        heading=text.splitlines()[0] if text else ''
        if re.search(r'字体|字太小|字号',question):
            if '微信' not in question and '微信' in heading: continue
            if '微信' in question and '微信' not in text: continue
        if re.search(r'收到|别人.{0,3}语音',question) and re.search(r'发语音|发送语音',heading): continue
        if re.search(r'(?:发|包|给).{0,12}红包',question) and '抢红包' not in question and re.search(r'抢红包|查看零钱',heading): continue
        if re.search(r'不删.{0,4}照片|保留.{0,4}照片',question) and re.search(r'(?:清理|删除|删).{0,8}照片',heading): continue
        if is_ios_question(question) and not re.search(r'苹果|iPhone|iOS',c.get('platform') or '',re.I): continue
        if '学生票' in question and not re.search(r'学生票|学生优惠|学生资质',text): continue
        region=re.search(r'武汉|上海|北京|广州|深圳',question)
        if region and re.search(r'医保|津贴|补贴|报销',question):
            if region.group() not in (c.get('region') or '') or not c.get('valid_until') or not documented_review(c): continue
        if re.match(r'^\s*(?:温馨提示|免责声明)[：:]',text): continue
        example=_question_similarity(question,c.get('questions'))
        coverage=len(query_grams & _grams(text))/max(1,len(query_grams))
        vector=c.get('vector_score') or 0.0
        if vector < .55 and example < .60 and not active_profiles(question): continue
        if not active_profiles(question) and example < .45 and (vector < .62 or coverage < .12): continue
        rank=.65*vector+.20*example+.15*min(1.0,coverage)
        c['rerank_score']=rank
        c['question_similarity']=example
        reranked.append((cid,rrf))
    reranked.sort(key=lambda x:(-by_id[x[0]]['rerank_score'], -x[1], str(by_id[x[0]]['source']), by_id[x[0]].get('chunk_index',0)))

    out = []
    per_source_count = {}
    for cid, rrf in reranked:
        if final_min_rrf != FINAL_MIN_RRF and rrf < final_min_rrf:
            continue  # 显式覆盖旧参数时仍可用作候选诊断门槛；默认走范围约束及重排。
        c = by_id[cid]
        if out and c['rerank_score'] < by_id[reranked[0][0]]['rerank_score'] - .12:
            continue
        src = c["source"]
        if per_source_count.get(src, 0) >= max_per_source:
            continue
        per_source_count[src] = per_source_count.get(src, 0) + 1
        out.append({
            "source": src,
            "title": c.get("title") or src,
            "category": c.get("category") or "",
            "keywords": c.get("keywords") or "",
            "questions": c.get("questions") or "",
            "dir": c.get("dir") or "",
            "chunk_index": c.get("chunk_index"),
                    "document_id": c.get("document_id"),
                    "chunk_id": c.get("chunk_id"),
                    "document_version": c.get("document_version"),
                    "source_url": c.get("source_url"),
                    "updated_at": c.get("updated_at"),
                    "region": c.get("region"),
            "best_chunk": c.get("text") or "",
            "score": round(rrf, 5),
            "rerank_score": round(c['rerank_score'], 5),
            "question_similarity": round(c['question_similarity'], 5),
            **{key:c.get(key) for key in ('platform','review_status','reviewed_by','reviewed_at','valid_until','source_scope','review_notes')},
            "keyword_score": round(c["keyword_score"], 3) if c.get("keyword_score") is not None else None,
            "vector_score": round(c["vector_score"], 4) if c.get("vector_score") is not None else None,
            "channel": "hybrid" if (cid in rank_vec and cid in rank_kw)
                       else ("vector" if cid in rank_vec else "keyword"),
        })
        if len(out) >= top_k:
            break

    if not out:
        return {"channel": "none", "threshold": vector_threshold,
                "results": [], "reason": "below_final_threshold"}
    return {"channel": "hybrid" if any(o["channel"] == "hybrid" for o in out) else out[0]["channel"],
            "threshold": vector_threshold, "results": out}


def _doc_meta(source: str, db_path: str = None) -> dict:
    db_path = db_path or _ri.get_default_db_path()
    con = _ri._conn(db_path)
    row = con.execute(
        f"SELECT title,category,keywords,questions,dir,text FROM {_ri.TABLE} WHERE source=? ORDER BY chunk_index LIMIT 1",
        (source,)).fetchone()
    con.close()
    if not row:
        return {"source": source, "title": source, "category": "", "keywords": "",
                "questions": "[]", "dir": "", "best_chunk": ""}
    return {"source": source, "title": row[0], "category": row[1], "keywords": row[2],
            "questions": row[3], "dir": row[4], "best_chunk": row[5][:80]}


if __name__ == "__main__":
    import time
    t0 = time.time()
    emb = _ri.build_embedder()
    db = _ri.get_default_db_path()
    ei = ensure_index(db, emb)
    print("ensure_index:", {k: ei[k] for k in ("rebuilt", "reason")}, "stats=", ei.get("stats"))
    for q in ("高血压怎么控制", "怎么测血压才最准确", "微信怎么发红包转账", "明天适合去海边钓鱼吗"):
        r = hybrid_retrieve(q, embedder=emb, db_path=db)
        print(f"\n[{r['channel']}] {q}")
        for x in r["results"][:3]:
            print(f"   - {x['title']}  rrf={x['score']} vec={x['vector_score']} kw={x['keyword_score']} ch={x['channel']}")
            print(f"     chunk: {x['best_chunk'][:80].strip()}")

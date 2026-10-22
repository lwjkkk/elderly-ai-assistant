# -*- coding: utf-8 -*-
"""
10.24 #7 RAG 升级——原型：93 篇既有 TXT 的稳定分块 + metadata 保留 + 本地 bge-small-zh embedding + SQLite 向量表/索引。

设计要点（与 10.25 的混合排序解耦，本文件只做原型）：
1. 解析 TXT 的 标题/关键词/分类/问题 元数据，正文（回答：之后）稳定分块；
2. 每块一个 embedding（bge-small-zh，本地模型，D 盘），向量以 FLOAT32 BLOB 存 SQLite；
3. 索引可重复重建（DROP + 重建），旧版关键词检索（core/rag.py）原样保留，作为对照；
4. 检索：余弦相似度 top_k，返回块全文 + 完整 metadata + 得分。

依赖：sentence-transformers、torch(cpu)、numpy、sqlite3(标准库)。
模型缓存：D:\\models（HF_HOME / cache_folder），模型 BAAI/bge-small-zh-v1.5。
"""
import os
import re
import sqlite3
import json
import glob
import time
import hashlib

import numpy as np

# ---------- 配置 ----------
MODEL_NAME = "BAAI/bge-small-zh-v1.5"
MODEL_DIR = os.environ.get("BGE_MODEL_DIR", r"D:\models")  # 模型缓存目录，可用环境变量覆盖（Linux 服务器用 /root/models）
EMBED_DIM = 512                               # bge-small-zh-v1.5 输出维度
MAX_CHUNK = 300                               # 单块最大字符数（超过再细分）
TABLE = "knowledge_chunks"


# ---------- 1. TXT 解析与 metadata 保留 ----------
def parse_doc(path: str, kb_dir: str = None) -> dict:
    """
    解析单篇知识库 TXT：
      - 元数据：标题/关键词/分类/问题（可多条）
      - 正文：回答：之后的内容
    编码兼容 UTF-8/GBK。返回 dict，正文为空或元数据缺失时仍保留已解析字段。
    """
    kb_dir = kb_dir or get_kb_dir()
    content = None
    for enc in ("utf-8", "gbk"):
        try:
            with open(path, encoding=enc) as f:
                content = f.read()
            break
        except UnicodeDecodeError:
            continue
    if content is None:
        with open(path, encoding="utf-8", errors="replace") as f:
            content = f.read()

    meta = {
        "source": os.path.basename(path),
        "dir": os.path.relpath(os.path.dirname(path), kb_dir) if path else "",
        "title": "",
        "category": "",
        "keywords": "",
        "questions": [],
        "source_url": None, "updated_at": None, "region": None,
    }
    rel_path = os.path.relpath(path, kb_dir).replace("\\", "/")
    meta["document_id"] = hashlib.sha256(rel_path.encode("utf-8")).hexdigest()[:24]
    meta["document_version"] = hashlib.sha256(content.encode("utf-8")).hexdigest()[:16]
    lines = content.splitlines()
    in_body = False
    body_lines = []
    for ln in lines:
        s = ln.strip()
        if s.lower().startswith("回答"):
            in_body = True
            continue
        if not in_body:
            m = re.match(r"^(标题|关键词|分类|问题|来源网址|来源URL|source_url|更新时间|地区)\s*[：:]\s*(.*)$", s, re.I)
            if m:
                k, v = m.group(1).lower(), m.group(2).strip()
                if k == "问题":
                    meta["questions"].append(v)
                elif k == "标题".lower():
                    meta["title"] = v
                elif k == "关键词".lower():
                    meta["keywords"] = v
                elif k == "分类".lower():
                    meta["category"] = v
                elif k in ("来源网址", "来源url", "source_url"):
                    meta["source_url"] = v or None
                elif k == "更新时间":
                    meta["updated_at"] = v or None
                elif k == "地区":
                    meta["region"] = v or None
            continue
        body_lines.append(ln)
    meta["body"] = "\n".join(body_lines).strip()
    return meta


def chunk_text(body: str, max_chunk: int = MAX_CHUNK) -> list:
    """
    稳定分块：先按空行切段落；段落过长再按“一、/1. /1.1”等小标题或句末标点细分。
    纯规则、无随机，保证索引可重复构建。
    """
    if not body:
        return []
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()]
    chunks = []
    for para in paragraphs:
        if len(para) <= max_chunk:
            chunks.append(para)
            continue
        # 按小标题式行/句末标点细分
        pieces = re.split(r"(?<=[。！？；：])\s*|\n", para)
        buf = ""
        for piece in pieces:
            piece = piece.strip()
            if not piece:
                continue
            if buf and len(buf) + len(piece) > max_chunk:
                chunks.append(buf)
                buf = piece
            else:
                buf = (buf + piece) if buf else piece
        if buf:
            chunks.append(buf)
    # 丢弃纯空块
    return [c for c in chunks if c.strip()]


# ---------- 2. Embedding ----------
def build_embedder():
    """加载本地 bge-small-zh（D 盘缓存，已下载则不重复联网）。"""
    from sentence_transformers import SentenceTransformer
    # 兜底：若环境变量未指到 D 盘，也强制用 D 盘缓存目录
    os.environ.setdefault("HF_HOME", MODEL_DIR)
    return SentenceTransformer(MODEL_NAME, cache_folder=MODEL_DIR)


def embed_texts(embedder, texts: list) -> np.ndarray:
    """批量编码并 L2 归一化（归一化后余弦=点积）。"""
    vecs = embedder.encode(texts, normalize_embeddings=True, show_progress_bar=False)
    return np.asarray(vecs, dtype=np.float32)


# ---------- 3. SQLite 向量表/索引 ----------
def _conn(db_path: str):
    con = sqlite3.connect(db_path)
    return con


def build_index(kb_dir: str, db_path: str, embedder=None) -> dict:
    """
    遍历知识库所有 .txt，解析+分块+编码，写入 SQLite。
    - 可重复构建：DROP 旧表后重建（每次得到同一 schema）；
    - 保留 metadata：source/title/category/keywords/questions/dir/块序/原文。
    返回统计：docs / chunks / skipped。
    """
    os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
    docs = sorted(glob.glob(os.path.join(kb_dir, "**", "*.txt"), recursive=True))
    docs += sorted(glob.glob(os.path.join(kb_dir, "**", "*.md"), recursive=True))
    # 去重
    seen = set()
    docs = [d for d in docs if not (d in seen or seen.add(d))]

    con = _conn(db_path)
    cur = con.cursor()
    cur.execute(f"DROP TABLE IF EXISTS {TABLE}")
    cur.execute(f"""
        CREATE TABLE {TABLE} (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            source     TEXT NOT NULL,
            title      TEXT,
            category   TEXT,
            keywords   TEXT,
            questions  TEXT,
            dir        TEXT,
            chunk_index INTEGER NOT NULL,
            text       TEXT NOT NULL,
            metadata_json TEXT,
            embedding  BLOB NOT NULL
        )
    """)
    # 标量列索引（10.25 关键词混合排序与分类过滤用）
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_{TABLE}_source ON {TABLE}(source)")
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_{TABLE}_cat ON {TABLE}(category)")

    stats = {"docs": 0, "chunks": 0, "skipped": 0}
    rows = []
    pending_texts = []
    chunk_ids = []
    for path in docs:
        meta = parse_doc(path, kb_dir)
        if not meta["body"]:
            stats["skipped"] += 1
            continue
        chunks = chunk_text(meta["body"])
        stats["docs"] += 1
        for i, text in enumerate(chunks):
            pending_texts.append(text)
            chunk_ids.append(i)
            rows.append({
                "source": meta["source"], "title": meta["title"],
                "category": meta["category"], "keywords": meta["keywords"],
                "questions": json.dumps(meta["questions"], ensure_ascii=False),
                "dir": meta["dir"], "chunk_index": i, "text": text,
                "document_id": meta["document_id"],
                "document_version": meta["document_version"],
                "chunk_id": hashlib.sha256(
                    f"{meta['document_id']}:{meta['document_version']}:{i}:{text}".encode("utf-8")
                ).hexdigest()[:32],
                "source_url": meta["source_url"], "updated_at": meta["updated_at"],
                "region": meta["region"],
            })
        stats["chunks"] += len(chunks)

    if pending_texts:
        vecs = embed_texts(embedder, pending_texts)
        for r, vec in zip(rows, vecs):
            cur.execute(
                f"INSERT INTO {TABLE}(source,title,category,keywords,questions,dir,chunk_index,text,metadata_json,embedding) "
                f"VALUES(?,?,?,?,?,?,?,?,?,?)",
                (r["source"], r["title"], r["category"], r["keywords"], r["questions"],
                 r["dir"], r["chunk_index"], r["text"],
                 json.dumps({"title": r["title"], "category": r["category"],
                             "keywords": r["keywords"], "questions": json.loads(r["questions"]),
                             "dir": r["dir"], "chunk_index": r["chunk_index"],
                             "document_id": r["document_id"],
                             "chunk_id": r["chunk_id"],
                             "document_version": r["document_version"],
                             "source_url": r["source_url"], "updated_at": r["updated_at"],
                             "region": r["region"]}, ensure_ascii=False),
                 vec.astype(np.float32).tobytes()))
    con.commit()
    con.close()
    stats["dim"] = EMBED_DIM
    stats["db"] = os.path.abspath(db_path)
    return stats


# ---------- 4. 检索（余弦） ----------
def _read_vectors(con, limit=None):
    sql = f"SELECT id, embedding FROM {TABLE}"
    cur = con.cursor()
    if limit:
        cur.execute(sql + f" LIMIT {limit}")
    else:
        cur.execute(sql)
    ids, mat = [], []
    for rid, blob in cur.fetchall():
        ids.append(rid)
        mat.append(np.frombuffer(blob, dtype=np.float32))
    if not ids:
        return ids, np.zeros((0, EMBED_DIM), dtype=np.float32)
    return ids, np.vstack(mat).astype(np.float32)


def query_index(db_path: str, question: str, embedder=None, top_k: int = 3) -> list:
    """
    向量检索：把问题编码后与全部块向量做余弦（向量已归一化，余弦=点积），返回 top_k。
    每次检索内部重连读取，避免跨连接状态错乱。
    返回 [{id, source, title, category, keywords, questions, chunk_index, text, dir, score}]。
    """
    con = _conn(db_path)
    qv = embed_texts(embedder, [question])[0].reshape(1, -1)
    ids, vecs = _read_vectors(con)
    scores = (vecs @ qv.T).ravel()  # 归一化后即余弦
    order = np.argsort(-scores)[:top_k]
    out = []
    for idx in order:
        rid = ids[idx]
        cur = con.cursor()
        row = cur.execute(
            f"SELECT source,title,category,keywords,questions,chunk_index,text,dir FROM {TABLE} WHERE id=?", (rid,)
        ).fetchone()
        out.append({
            "id": rid,
            "source": row[0], "title": row[1], "category": row[2], "keywords": row[3],
            "questions": row[4], "chunk_index": row[5], "text": row[6], "dir": row[7],
            "score": round(float(scores[idx]), 4),
        })
    con.close()
    return out


# ---------- 工具 ----------
def get_kb_dir():
    """返回知识库根目录（与 core/rag.py 的 KNOWLEDGE_BASE_DIR 对齐）。"""
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "knowledge_base"))


def get_default_db_path():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "knowledge_vectors.db"))


def index_version() -> str | None:
    """Return the knowledge fingerprint from the current hybrid index metadata."""
    path = get_default_db_path()
    if not os.path.isfile(path):
        return None
    try:
        con = _conn(path)
        row = con.execute(
            "SELECT value FROM knowledge_index_meta WHERE key='kb_fingerprint'"
        ).fetchone()
        con.close()
        return row[0] if row else None
    except Exception:
        return None


if __name__ == "__main__":
    t0 = time.time()
    print("[build] 加载 embedder...")
    emb = build_embedder()
    kb = get_kb_dir()
    db = get_default_db_path()
    print(f"[build] 知识库: {kb}")
    st = build_index(kb, db, emb)
    st["elapsed_s"] = round(time.time() - t0, 1)
    print(json.dumps(st, ensure_ascii=False))

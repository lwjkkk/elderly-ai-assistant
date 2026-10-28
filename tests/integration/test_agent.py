
# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
# 中秋 A 优先 - 冒烟测试：验证 Qwen、RAG 和 get_agent_answer() 端到端跑通
# 运行方式（在项目根目录）：
#   python test_agent.py
# 或单独测试 RAG 检索：
#   python test_agent.py --rag-only "医保卡怎么挂号"

import sys

from core.rag import retrieve_from_knowledge_base


def test_rag(question: str):
    """单独验证 RAG 检索，方便调试 C 同学的知识库文件"""
    print("=" * 50)
    print(f"测试 RAG 检索，问题：{question}")
    results = retrieve_from_knowledge_base(question)
    if not results:
        print("（没有检索到相关内容——检查知识库目录下是否有 txt/md 文件，且关键词是否匹配）")
        return
    for i, r in enumerate(results, 1):
        print(f"\n--- 命中 {i}：来源 {r['source']} ---")
        print(r["content"][:500])


def test_full(question: str):
    """端到端调用 get_agent_answer()，验证返回约定格式"""
    from core.agent import get_agent_answer

    print("=" * 50)
    print(f"测试 get_agent_answer()，问题：{question}")
    result = get_agent_answer(question)
    print("模块 module ：", result["module"])
    print("答案 answer ：", result["answer"][:300], "...")
    print("步骤 steps  ：", len(result["steps"]), "条")
    print("免责声明    ：", result["disclaimer"][:40], "...")


if __name__ == "__main__":
    # 用法：python test_agent.py 或 python test_agent.py --rag-only "问题"
    if len(sys.argv) >= 3 and sys.argv[1] == "--rag-only":
        test_rag(sys.argv[2])
    else:
        # 先看知识库有没有内容
        from core.rag import _load_documents

        docs = _load_documents()
        print(f"当前知识库共读到 {len(docs)} 个文件")
        for d in docs:
            print(f"  - {d['source']}")
        print()

        test_rag("怎么调大手机字体")
        test_full("怎么把手机字体调大？")
        test_full("用医保卡怎么挂号？")

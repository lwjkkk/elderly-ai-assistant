
# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
# 批量自测脚本：跑一组问题，验证模块映射与回答质量，并把结果写入 docs/self_test_results.md
# 运行：python batch_test.py（当前配置的模型服务，可能使用额度）
# 说明：每个问题会真实调用当前配置的生成模型，视模型速度每条约 5~30 秒。

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core.agent import get_agent_answer

# (问题, 期望模块) —— 覆盖三个模块
QUESTIONS = [
    ("微信怎么发语音消息给别人？", "phone"),
    ("怎么把手机字体调大？", "phone"),
    ("怎么用医保卡挂号？", "services"),
    ("怎么识别诈骗电话？", "daily_life"),
    ("晚上睡不着觉有什么办法？", "daily_life"),
    ("怎么用手机交水电费？", "services"),
]


def main():
    os.makedirs("docs", exist_ok=True)
    out = ["# 批量自测结果", "", f"- 运行时间：{__import__('datetime').datetime.now():%Y-%m-%d %H:%M}", ""]
    for i, (q, expect) in enumerate(QUESTIONS, 1):
        print(f"\n[{i}/{len(QUESTIONS)}] 问题：{q}")
        r = get_agent_answer(q)
        match = "OK" if r["module"] == expect else "不一致"
        print(f"  模块：{r['module']}（期望 {expect}）→ {match}｜步骤数：{len(r['steps'])}")
        out.append(f"## {i}. 问题：{q}")
        out.append(f"- 期望模块：{expect}｜实际模块：{r['module']}｜{match}")
        out.append(f"- 步骤数：{len(r['steps'])}")
        out.append(f"- 回答摘要：{r['answer'][:150]}")
        out.append("")

    with open("docs/self_test_results.md", "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"\n完成，结果已写入 docs/self_test_results.md")


if __name__ == "__main__":
    main()

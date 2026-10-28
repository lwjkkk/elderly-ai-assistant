
# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
# Day5 回归：原有三大知识库迁移 + health 分支 + 模块识别
# 只测检索与分类（不调用 LLM），快且稳定。

from core.rag import retrieve_from_knowledge_base, _load_documents
from core.agent import _detect_module

lines = []
def ok(cond, msg):
    lines.append(("PASS " if cond else "FAIL ") + msg)

# 1. 知识库文档总数（手机20 + 办事20 + 生活21 = 61）
docs = _load_documents()
ok(len(docs) >= 55, f"知识库文档数={len(docs)}（应≥55）")

# 2. 三大类问答检索命中
cases = [
    ("微信怎么发语音消息", "phone", "微信发语音消息"),
    ("手机怎么连WiFi", "phone", "手机连WiFi"),
    ("异地就医备案怎么办", "services", "异地就医备案"),
    ("怎么在网上挂号", "services", "医院网上挂号"),
    ("隔夜菜能不能吃", "daily_life", "隔夜菜"),
    ("怎么识别网络诈骗", "daily_life", "网络诈骗"),
]
for q, expect_mod, expect_src in cases:
    hits = retrieve_from_knowledge_base(q)
    got = hits[0]["source"] if hits else ""
    ok(bool(hits) and expect_src in got, f"[{expect_mod}] '{q}' -> 命中《{got}》")

# 3. health 兜底模块识别
for q in ["血压多少算正常", "糖尿病饮食要注意什么", "老年人骨质疏松怎么办"]:
    ok(_detect_module(q) == "health", f"健康类识别: '{q}' -> {_detect_module(q)}")

# 4. category 类别过滤
phone_only = retrieve_from_knowledge_base("怎么操作", category="phone")
ok(all("phone_tutorial" in h["dir"] for h in phone_only) and bool(phone_only),
   f"category=phone 过滤生效（{len(phone_only)}条，均在手机教程目录）")
health_only = retrieve_from_knowledge_base("血压 血糖 用药", category="health")
ok(health_only == [], f"category=health 当前{len(health_only)}条（knowledge_base/health 目录待 C 建立，代码已支持）")

# 汇总
fails = [x for x in lines if x.startswith("FAIL")]
lines.append("")
lines.append(f"结果：{len(lines)-len(fails)-1} 通过 / {len(fails)} 失败")
lines.append("全部通过" if not fails else "存在失败项：\n" + "\n".join(fails))

with open("day5_result.txt", "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("done")

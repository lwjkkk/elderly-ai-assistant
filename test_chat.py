# 真实端到端测试 /api/chat（需在 .env 填入真实 DASHSCOPE_API_KEY）
# 用法：
#   python test_chat.py   只测文字问答（含 health）

import sys

from fastapi.testclient import TestClient
from main import app

c = TestClient(app)

questions = [
    "微信怎么发语音消息？",        # 手机教程
    "异地就医备案怎么办？",        # 办事
    "高血压怎么管理？",            # health
    "隔夜菜能不能吃？",            # 日常生活
]

for q in questions:
    print("=" * 50)
    print("问：", q)
    r = c.post("/api/chat", json={"question": q})
    print("状态码：", r.status_code)
    if r.status_code == 200:
        d = r.json()
        print("模块 module：", d.get("module"))
        print("回答 answer：", d.get("answer", "")[:300])
        print("步骤数 steps：", len(d.get("steps", [])))
        print("免责声明：", d.get("disclaimer", "")[:60])
    else:
        print("返回：", r.text[:300])

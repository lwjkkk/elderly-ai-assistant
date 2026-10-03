# 拍照查药独立测试：python test_drug.py 药盒图片路径
# 自动 读图->base64->登录->调用 /api/drugs/query->打印结果（首次会加载PaddleOCR，较慢）
import base64
import sys

# 必须最先导入 torch：让进程先加载新版 VC++ 运行库，
# 否则后续 import 的其它库可能先占住旧版 DLL，导致 torch 的 shm.dll 报 WinError 127
import torch  # noqa: F401

from fastapi.testclient import TestClient

from main import app

c = TestClient(app)

# 1) 读图转 base64
if len(sys.argv) < 2:
    print("用法：python test_drug.py 药盒图片路径")
    sys.exit(1)
path = sys.argv[1]
with open(path, "rb") as f:
    image_base64 = base64.b64encode(f.read()).decode()

# 2) 登录老人拿 token
login = c.post("/api/auth/login", json={"phone": "13800000001", "password": "123456"})
if login.status_code != 200:
    print("登录失败：", login.status_code, login.json())
    sys.exit(1)
token = login.json()["access_token"]

# 3) 调用查药（首次加载 OCR 模型可能要等几十秒）
print("正在识别并解读，请稍候……")
r = c.post(
    "/api/drugs/query",
    headers={"Authorization": f"Bearer {token}"},
    json={"image_base64": image_base64},
)

print("状态码：", r.status_code)
if r.status_code != 200:
    print(r.text)
    sys.exit(1)

data = r.json()
print("\n【OCR 识别文字】\n", data.get("ocr_text", ""))
print("\n【大白话解读】\n", data.get("explanation", ""))
print("\n【免责声明】\n", data.get("disclaimer", ""))

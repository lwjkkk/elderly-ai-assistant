# 配置文件 - API Key 和模型参数
import os
from dotenv import load_dotenv

# 自动加载项目根目录的 .env 文件（必须在读取环境变量前调用）
load_dotenv()

# 通义千问 / 本地开源模型配置
# 说明：当前使用本地 Ollama 部署的开源模型（qwen2:7b），免费、可离线、数据不出本地。
# 若改用阿里云 API，只需把 LLM_BASE_URL 改回 https://dashscope.aliyuncs.com/compatible-mode/v1，
# 并设置 DASHSCOPE_API_KEY。
DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY", "")

# 模型服务地址：本地 Ollama 的 OpenAI 兼容接口
LLM_BASE_URL = "http://localhost:11434/v1"

# 文本模型（Ollama 中已拉取的模型名）
QWEN_MODEL_NAME = "qwen2:7b"

# 模型调用参数
QWEN_MAX_TOKENS = 1024        # 最大生成 token 数
QWEN_TEMPERATURE = 0.7        # 温度，越低越稳定
QWEN_TIMEOUT = 180            # 网络超时时间（秒）；本地CPU跑7B模型生成长回答较慢，给足时间
QWEN_MAX_RETRIES = 2          # 失败重试次数

# OCR 配置
OCR_LANG = "ch"
OCR_USE_GPU = False
# OCR 模型目录：必须是纯英文绝对路径。默认位于后端项目目录下，避免写入受限的 D 盘根目录。
# Paddle 推理引擎无法打开中文用户名路径（如 C:/Users/张三/.paddleocr/...）下的模型文件，
# 统一放到 D 盘后端目录的纯英文子目录，由 ocr.py 显式传给 det/rec/cls 三个模型子目录。
_DEFAULT_OCR_MODEL_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "ocr_models")
)
OCR_MODEL_DIR = os.getenv("OCR_MODEL_DIR", _DEFAULT_OCR_MODEL_DIR)

# RAG 知识库路径
KNOWLEDGE_BASE_DIR = "./knowledge_base"

# 服务器配置
# 0.0.0.0 监听所有网卡，局域网/前端/手机可通过 http://<本机IP>:8000 访问
HOST = "0.0.0.0"
PORT = 8000

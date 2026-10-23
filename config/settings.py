# 配置文件 - API Key 和模型参数
import os
from dotenv import load_dotenv

# 自动加载项目根目录的 .env 文件（必须在读取环境变量前调用）
load_dotenv()

# 通义千问 / 阿里云百炼云 API 配置
# 当前默认走阿里云百炼 OpenAI 兼容接口（qwen3.7-plus），数据走云端推理。
# 模型地址与模型名通过环境变量 LLM_BASE_URL / QWEN_MODEL_NAME 切换，
# 如需切到本地 Ollama / vLLM，在 .env 覆盖即可，不改代码。
# API Key 从 .env 的 DASHSCOPE_API_KEY 读取，不硬编码到代码。
DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY", "")

# 模型服务地址：默认阿里云百炼 OpenAI 兼容接口；本地部署时覆盖为 http://localhost:11434/v1 等
LLM_BASE_URL = os.getenv(
    "LLM_BASE_URL",
    "https://dashscope.aliyuncs.com/compatible-mode/v1",
)

# 文本模型：默认百炼 qwen3.7-plus；本地切换时改为 qwen2.5:7b / qwen2.5:3b 等
QWEN_MODEL_NAME = os.getenv("QWEN_MODEL_NAME", "qwen3.7-plus")

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
# 此目录保留兼容；v3 自定义权重使用 OCR_DET_MODEL_DIR / OCR_REC_MODEL_DIR。
# 默认固定 PP-OCRv6_medium_det/rec（可由 OCR_DET_MODEL / OCR_REC_MODEL 覆盖），使用 PaddleX 缓存。
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

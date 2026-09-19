# 配置文件 - API Key 和模型参数
import os

# 通义千问 API 配置（从环境变量读取，不要硬编码）
DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY", "")
QWEN_MODEL_NAME = "qwen-turbo"

# 模型调用参数
QWEN_MAX_TOKENS = 1024        # 最大生成 token 数
QWEN_TEMPERATURE = 0.7        # 温度，越低越稳定
QWEN_TIMEOUT = 30             # 网络超时时间（秒）
QWEN_MAX_RETRIES = 2          # 失败重试次数

# OCR 配置
OCR_LANG = "ch"
OCR_USE_GPU = False

# RAG 知识库路径
KNOWLEDGE_BASE_DIR = "./knowledge_base"

# 服务器配置
HOST = "127.0.0.1"
PORT = 8000

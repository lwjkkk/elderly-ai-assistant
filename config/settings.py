# 配置文件 - API Key 和模型参数
import os

# 通义千问 API 配置（后面去阿里云申请）
DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY", "在此填入你的API Key")
QWEN_MODEL_NAME = "qwen-turbo"

# OCR 配置
OCR_LANG = "ch"
OCR_USE_GPU = False

# RAG 知识库路径
KNOWLEDGE_BASE_DIR = "./knowledge_base"

# 服务器配置
HOST = "127.0.0.1"
PORT = 8000

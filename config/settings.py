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
QWEN_TIMEOUT = 60             # 网络超时时间（秒）
QWEN_MAX_RETRIES = 2          # 失败重试次数

# OCR 配置
OCR_LANG = "ch"
OCR_USE_GPU = False

# RAG 知识库路径
KNOWLEDGE_BASE_DIR = "./knowledge_base"

# 服务器配置
HOST = "127.0.0.1"
PORT = 8000

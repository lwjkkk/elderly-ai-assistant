# 通义千问大模型调用封装（使用 OpenAI 兼容模式）

# 说明：dashscope SDK 在 Windows 上处理中文请求时会报
#       'latin-1' codec can't encode characters 的编码 bug。
#       这里改用阿里云官方支持的 OpenAI 兼容接口（compatible-mode），
#       用 openai 包调用，稳定且不依赖 dashscope 的 HTTP 编码实现。

import logging
import time
from urllib.parse import urlsplit

from openai import OpenAI

from core.sensitive import sanitize
from core.model_fallback import ModelQuotaExhausted, namespace, run_with_fallback
from config.settings import (
    DASHSCOPE_API_KEY,
    LLM_BASE_URL,
    QWEN_MODEL_NAME,
    QWEN_FALLBACK_MODEL_NAME,
    QWEN_MAX_TOKENS,
    QWEN_TEMPERATURE,
    QWEN_TIMEOUT,
    QWEN_MAX_RETRIES,
)

logger = logging.getLogger(__name__)

# 可复用的 OpenAI 兼容客户端，地址由配置指定。
_client = None


def _get_client() -> OpenAI:
    """懒加载一个全局可复用的客户端"""
    global _client
    if _client is None:
        # 本地 Ollama 完全忽略 Authorization 头，传任意 ASCII 占位即可；
        # 若 base_url 指向云端 API（阿里云百炼），才使用真实 key。
        key = "ollama" if "localhost" in LLM_BASE_URL else (DASHSCOPE_API_KEY or "dummy")
        _client = OpenAI(
            api_key=key,
            base_url=LLM_BASE_URL,
            timeout=QWEN_TIMEOUT,
            max_retries=0,  # 重试只由外层统一控制，避免 SDK 重试叠加放大等待。
        )
    return _client


def _validate_api_key():
    """校验 API Key：本地 Ollama 不需要 key，仅指向云端 API 时才需要"""
    if "localhost" in LLM_BASE_URL:
        return
    if not DASHSCOPE_API_KEY:
        raise ValueError(
            "未配置通义千问 API Key，请在环境变量中设置 DASHSCOPE_API_KEY"
        )


def complete_with_fallback(messages, *, max_tokens, temperature, timeout=None):
    """A shared model policy for answers, reports and bounded semantic triage."""
    _validate_api_key()
    deadline = time.monotonic() + timeout if timeout is not None else None
    host = urlsplit(LLM_BASE_URL).hostname or ''
    bailian = host in ('dashscope.aliyuncs.com', 'dashscope-intl.aliyuncs.com',
                       'dashscope-us.aliyuncs.com') or host.endswith('.maas.aliyuncs.com')

    def request(model):
        client = _get_client()
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('模型调用已超时')
            client = client.with_options(timeout=remaining, max_retries=0)
        options = dict(model=model, messages=messages, max_tokens=max_tokens,
                       temperature=temperature)
        if bailian and model.startswith(('qwen3.', 'qwen3-')):
            options['extra_body'] = {'enable_thinking': False}
        return client.chat.completions.create(**options)

    return run_with_fallback(QWEN_MODEL_NAME, QWEN_FALLBACK_MODEL_NAME, request,
                             scope=namespace('text', LLM_BASE_URL, DASHSCOPE_API_KEY))


def call_qwen(system_prompt: str, user_question: str) -> str:
    """
    调用通义千问模型，返回模型生成的文字回答

    参数：
        system_prompt: 系统提示词（控制回答风格）
        user_question: 用户提出的问题（文字，含语音转文字）

    返回：
        模型生成的文本回答
    """
    _validate_api_key()

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_question},
    ]

    last_error = None
    for attempt in range(1, QWEN_MAX_RETRIES + 1):
        try:
            logger.info("第 %d 次请求文本模型主备链", attempt)

            started = time.perf_counter()
            response = complete_with_fallback(
                messages,
                max_tokens=QWEN_MAX_TOKENS,
                temperature=QWEN_TEMPERATURE,
                timeout=QWEN_TIMEOUT,
            )

            answer = response.choices[0].message.content
            if answer:
                usage = getattr(response, "usage", None)
                logger.info("llm_timing seconds=%.3f attempt=%d prompt_tokens=%s completion_tokens=%s",
                            time.perf_counter() - started, attempt,
                            getattr(usage, "prompt_tokens", None), getattr(usage, "completion_tokens", None))
                # 返回前做违禁词 / 医疗绝对化用语兜底过滤
                cleaned, blocked = sanitize(answer.strip())
                if blocked:
                    logger.warning("回答命中高危违禁词，已替换为兜底话术")
                return cleaned

            last_error = RuntimeError("模型返回为空")

        except ModelQuotaExhausted:
            # A retry cannot restore free quota and would only delay the user.
            raise
        except Exception as e:
            logger.warning("文本模型调用失败 attempt=%d error_type=%s", attempt, type(e).__name__)
            last_error = e
            if attempt < QWEN_MAX_RETRIES:
                time.sleep(1)  # 等 1 秒再重试

    # 所有重试都失败
    raise RuntimeError(f"通义千问调用失败（错误类型：{type(last_error).__name__}）") from None

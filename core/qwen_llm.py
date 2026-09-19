# 通义千问大模型调用封装

import dashscope
from dashscope import Generation
import logging
import time

from config.settings import (
    DASHSCOPE_API_KEY,
    QWEN_MODEL_NAME,
    QWEN_MAX_TOKENS,
    QWEN_TEMPERATURE,
    QWEN_TIMEOUT,
    QWEN_MAX_RETRIES,
)

logger = logging.getLogger(__name__)


def _validate_api_key():
    """校验 API Key 是否已配置"""
    if not DASHSCOPE_API_KEY:
        raise ValueError(
            "未配置通义千问 API Key，请在环境变量中设置 DASHSCOPE_API_KEY"
        )


def call_qwen(system_prompt: str, user_question: str, image_base64: str = None) -> str:
    """
    调用通义千问模型，返回模型生成的文字回答

    参数：
        system_prompt: 系统提示词（控制回答风格）
        user_question: 用户提出的问题
        image_base64: 可选，用户上传的手机截图（base64编码）

    返回：
        模型生成的文本回答

    异常：
        ValueError: API Key 未配置或无效
        TimeoutError: 网络请求超时
        RuntimeError: 其他调用失败
    """
    _validate_api_key()

    # 构造消息列表
    messages = [
        {"role": "system", "content": system_prompt},
    ]

    # 如果有截图，用多模态方式传入（qwen-vl 系列支持图片）
    if image_base64:
        user_content = [
            {"image": f"data:image/png;base64,{image_base64}"},
            {"text": user_question},
        ]
        messages.append({"role": "user", "content": user_content})
        # 有图片时使用视觉模型
        model_name = "qwen-vl-plus"
    else:
        messages.append({"role": "user", "content": user_question})
        model_name = QWEN_MODEL_NAME

    # 带重试的调用逻辑
    last_error = None
    for attempt in range(1, QWEN_MAX_RETRIES + 1):
        try:
            logger.info(f"第 {attempt} 次调用通义千问，模型：{model_name}")

            response = Generation.call(
                api_key=DASHSCOPE_API_KEY,
                model=model_name,
                messages=messages,
                max_tokens=QWEN_MAX_TOKENS,
                temperature=QWEN_TEMPERATURE,
                timeout=QWEN_TIMEOUT,
                result_format="message",
            )

            # 判断返回状态
            if response.status_code == 200:
                answer = response.output.choices[0].message.content
                # 如果返回的是列表（多模态情况），拼接文字
                if isinstance(answer, list):
                    answer = "".join(
                        item.get("text", "") for item in answer if "text" in item
                    )
                logger.info("通义千问调用成功")
                return answer
            else:
                # API 返回错误状态码
                error_msg = f"API返回错误 - 状态码: {response.status_code}, 信息: {response.message}"
                logger.error(error_msg)

                # API Key 无效，不重试，直接抛出
                if response.status_code in (401, 403):
                    raise ValueError(f"API Key 无效或权限不足，请检查 DASHSCOPE_API_KEY 配置。详细信息：{response.message}")

                last_error = RuntimeError(error_msg)

        except (ValueError, PermissionError):
            # API Key 问题，直接向上抛，不重试
            raise
        except Exception as e:
            # 网络超时、连接失败等，可以重试
            logger.warning(f"第 {attempt} 次调用失败：{e}")
            last_error = e
            if attempt < QWEN_MAX_RETRIES:
                time.sleep(1)  # 等1秒再重试

    # 所有重试都失败
    raise RuntimeError(f"通义千问调用失败（已重试{QWEN_MAX_RETRIES}次）：{last_error}")
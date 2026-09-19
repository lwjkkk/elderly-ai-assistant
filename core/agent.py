# 核心智能体逻辑

import logging
from core.prompt import SYSTEM_PROMPT, MODULE_PROMPTS
from core.qwen_llm import call_qwen

logger = logging.getLogger(__name__)


def get_agent_answer(question: str, image_base64: str = None) -> dict:
    """
    老年智能体主函数 - 前端调用这个接口

    入参：
        question: 用户的问题文字
        image_base64: 用户上传的手机截图（base64编码），没有就传None

    返回：
        {
            "answer": "完整回答",
            "module": "phone/services/daily_life",
            "steps": ["第一步...", "第二步..."],
            "disclaimer": "免责声明"
        }
    """
    try:
        # 1. 如果有截图，先调用 OCR 识别图片内容（后续阶段实现）
        # if image_base64:
        #     ocr_text = do_ocr(image_base64)
        #     question = f"{question}\n截图识别内容：{ocr_text}"

        # 2. 调用 RAG 检索知识库相关内容（后续阶段实现）
        # rag_context = retrieve_from_knowledge_base(question)

        # 3. 拼接最终问题（如果有 RAG 上下文，附加到问题后面）
        final_question = question
        # if rag_context:
        #     final_question = f"{question}\n\n参考资料：{rag_context}"

        # 4. 调用通义千问生成回答
        answer = call_qwen(
            system_prompt=SYSTEM_PROMPT,
            user_question=final_question,
            image_base64=image_base64,
        )

        # 5. 按适老化格式整理返回
        steps = _parse_steps(answer)

        return {
            "answer": answer,
            "module": _detect_module(question),
            "steps": steps,
            "disclaimer": "以上内容仅供参考，具体操作请以实际界面为准。如有疑问请咨询子女或社区工作人员。"
        }

    except ValueError as e:
        # API Key 配置问题
        logger.error(f"配置错误：{e}")
        return _error_response("系统配置异常，请联系管理员。")
    except TimeoutError as e:
        # 网络超时
        logger.error(f"请求超时：{e}")
        return _error_response("网络响应太慢了，请稍后再试一次。")
    except RuntimeError as e:
        # 其他运行时错误
        logger.error(f"调用异常：{e}")
        return _error_response("系统暂时出了点问题，请稍后再试。")
    except Exception as e:
        # 兜底异常处理
        logger.exception(f"未知错误：{e}")
        return _error_response("系统出了点状况，请稍后再试。")


def _parse_steps(answer: str) -> list:
    """从模型回答中提取操作步骤"""
    steps = []
    for line in answer.strip().split("\n"):
        line = line.strip()
        if line and any(line.startswith(prefix) for prefix in ["第一步", "第二步", "第三步", "第四步", "第五步", "第1步", "第2步", "第3步"]):
            steps.append(line)
    # 如果没提取到步骤，就把回答整体作为单步
    if not steps:
        steps = [answer]
    return steps


def _detect_module(question: str) -> str:
    """根据问题内容简单判断属于哪个模块"""
    phone_keywords = ["微信", "手机", "APP", "app", "软件", "怎么操作", "怎么打开", "怎么设置", "字体", "声音"]
    services_keywords = ["医保", "挂号", "社保", "养老", "公积金", "水电", "缴费"]

    for kw in phone_keywords:
        if kw in question:
            return "phone"
    for kw in services_keywords:
        if kw in question:
            return "services"
    return "daily_life"


def _error_response(tip: str) -> dict:
    """返回统一的错误格式"""
    return {
        "answer": tip,
        "module": "daily_life",
        "steps": [tip],
        "disclaimer": "以上内容仅供参考，具体操作请以实际界面为准。如有疑问请咨询子女或社区工作人员。"
    }

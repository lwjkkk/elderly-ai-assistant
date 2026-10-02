# 核心智能体逻辑

import os
import re
import logging
from core.prompt import SYSTEM_PROMPT, MODULE_PROMPTS
from core.qwen_llm import call_qwen
from core.rag import retrieve_from_knowledge_base

logger = logging.getLogger(__name__)

# 只认"第X步"开头的行（X 为中文或阿拉伯数字）
_STEP_RE = re.compile(r"^第([一二三四五六七八九十0-9０-９]{1,3})步")

# 知识库目录名 → 模块名的映射（RAG 命中时优先使用）
_DIR_TO_MODULE = {
    "phone_tutorial": "phone",
    "services": "services",
    "daily_life": "daily_life",
}


def _module_from_dir(dir_path: str) -> str:
    """根据知识库文件所在目录映射模块名，无法映射返回空字符串"""
    if not dir_path:
        return ""
    return _DIR_TO_MODULE.get(os.path.basename(dir_path), "")


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

        # 2. 调用 RAG 检索知识库相关内容
        rag_results = []
        rag_context = ""
        try:
            rag_results = retrieve_from_knowledge_base(question)
            if rag_results:
                rag_context = "\n\n".join(
                    f"【{r['source']}】\n{r['content']}" for r in rag_results
                )
        except Exception as e:
            logger.warning(f"RAG 检索失败：{e}")

        # 3. 拼接最终问题（如果有 RAG 上下文，附加到问题后面）
        final_question = question
        if rag_context:
            final_question = f"{question}\n\n参考资料：\n{rag_context}"

        # 4. 确定模块：优先按 RAG 命中的知识库目录映射，否则按问题关键词判断
        module = _detect_module(question)
        if rag_results:
            dir_module = _module_from_dir(rag_results[0].get("dir", ""))
            if dir_module:
                module = dir_module

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
            "module": module,
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


def _parse_steps(answer: str, max_steps: int = 6) -> list:
    """
    从模型回答中提取操作步骤。

    只认"第X步"开头的行（中文/阿拉伯数字均可），最多 max_steps 条，
    并按内容去重——避免把小模型回答里夹带的参考资料或幻觉文本算成步骤。
    如果没提取到任何步骤，把整个回答作为单步返回。
    """
    steps = []
    for line in answer.strip().split("\n"):
        line = line.strip()
        if not line:
            continue
        if _STEP_RE.match(line) and line not in steps:
            steps.append(line)
            if len(steps) >= max_steps:
                break
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

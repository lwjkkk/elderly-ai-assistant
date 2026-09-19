# 核心智能体逻辑

from core.prompt import SYSTEM_PROMPT, MODULE_PROMPTS


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
    # TODO: 中秋阶段实现
    # 1. 如果有截图，先调用 OCR 识别图片内容
    # 2. 调用 RAG 检索知识库相关内容
    # 3. 调用通义千问生成回答
    # 4. 按适老化格式整理返回

    return {
        "answer": f"你问的是：{question}，我正在学习中，目前只能回答基础问题。",
        "module": "daily_life",
        "steps": [f"目前收到你的问题：{question}"],
        "disclaimer": "以上内容仅供参考，具体操作请以实际界面为准。如有疑问请咨询子女或社区工作人员。"
    }

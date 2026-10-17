"""使用现有百炼凭据进行按需录音转写，不在发送时调用。"""
import base64
import os
from pathlib import Path

from openai import OpenAI
from config.settings import DASHSCOPE_API_KEY, LLM_BASE_URL


def transcribe_audio(path: Path, mime_type: str) -> str:
    if not DASHSCOPE_API_KEY:
        raise RuntimeError('服务端未配置语音转写凭据')
    client = OpenAI(api_key=DASHSCOPE_API_KEY,
                    base_url=os.getenv('ASR_BASE_URL', LLM_BASE_URL),
                    timeout=90, max_retries=0)
    data = base64.b64encode(path.read_bytes()).decode('ascii')
    result = client.chat.completions.create(
        model=os.getenv('ASR_MODEL', 'qwen3-asr-flash'),
        messages=[{'role': 'user', 'content': [
            {'type': 'input_audio', 'input_audio': {
                'data': f'data:{mime_type};base64,{data}'}}
        ]}],
        extra_body={'asr_options': {'enable_itn': True}},
    )
    text = (result.choices[0].message.content or '').strip()
    if not text:
        raise RuntimeError('没有识别到文字，请确认录音中有清晰讲话')
    return text

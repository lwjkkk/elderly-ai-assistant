"""使用现有百炼凭据进行按需录音转写，不在发送时调用。"""
import base64
import os
from pathlib import Path

from openai import OpenAI
from config.settings import DASHSCOPE_API_KEY, LLM_BASE_URL


def asr_configured() -> bool:
    return bool(os.getenv('ASR_API_KEY') or DASHSCOPE_API_KEY)


def transcribe_bytes(audio: bytes, mime_type: str, *, timeout: float = 25,
                     language: str | None = None) -> str:
    """Read-only transcription. No chat, vital write or notification side effects."""
    key = os.getenv('ASR_API_KEY') or DASHSCOPE_API_KEY
    if not key:
        raise RuntimeError('服务端未配置语音转写凭据')
    import httpx
    options = {'enable_itn':True}
    if language:
        options['language'] = language
    with OpenAI(api_key=key,base_url=os.getenv('ASR_BASE_URL',LLM_BASE_URL),
                timeout=httpx.Timeout(timeout,connect=min(5,timeout)),max_retries=0) as client:
        result = client.chat.completions.create(
            model=os.getenv('ASR_MODEL','qwen3-asr-flash'),
            messages=[{'role':'user','content':[{'type':'input_audio','input_audio':{
                'data':f'data:{mime_type};base64,'+base64.b64encode(audio).decode('ascii')}}]}],
            extra_body={'asr_options':options})
    text = (result.choices[0].message.content or '').strip()
    if not text:
        raise ValueError('没有识别到文字，请确认录音中有清晰讲话')
    if len(text)>5000:
        raise RuntimeError('语音服务返回内容异常，请重试')
    return text


def transcribe_audio(path: Path, mime_type: str) -> str:
    # Preserve the older consultation/family-message callers and their timeout.
    return transcribe_bytes(path.read_bytes(),mime_type,timeout=90)

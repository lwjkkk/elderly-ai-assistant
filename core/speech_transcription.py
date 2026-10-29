"""使用现有百炼凭据进行按需录音转写，不在发送时调用。"""
import base64
import io
import os
import time
import wave
from pathlib import Path
from urllib.parse import urlsplit

import httpx
import openai
from openai import OpenAI
from config.settings import DASHSCOPE_API_KEY, LLM_BASE_URL
from core.model_fallback import namespace, run_with_fallback


def asr_configured() -> bool:
    return bool(os.getenv('ASR_API_KEY') or DASHSCOPE_API_KEY)


def _compatible_transcription(audio, mime_type, model, key, base_url, timeout, language):
    options = {'enable_itn':True}
    if language:
        options['language'] = language
    with OpenAI(api_key=key,base_url=base_url,
                timeout=httpx.Timeout(timeout,connect=min(5,timeout)),max_retries=0) as client:
        result = client.chat.completions.create(
            model=model,
            messages=[{'role':'user','content':[{'type':'input_audio','input_audio':{
                'data':f'data:{mime_type};base64,'+base64.b64encode(audio).decode('ascii')}}]}],
            extra_body={'asr_options':options})
    return result.choices[0].message.content


def _native_endpoint(base_url):
    native = os.getenv('ASR_NATIVE_BASE_URL', '').strip()
    if native:
        return native.rstrip('/') + '/services/aigc/multimodal-generation/generation'
    url = urlsplit(base_url)
    host = url.hostname or ''
    if host not in ('dashscope.aliyuncs.com', 'dashscope-intl.aliyuncs.com',
                    'dashscope-us.aliyuncs.com') and not host.endswith('.maas.aliyuncs.com'):
        raise RuntimeError('备用语音模型需要配置 ASR_NATIVE_BASE_URL')
    return f'{url.scheme}://{url.netloc}/api/v1/services/aigc/multimodal-generation/generation'


def _native_transcription(audio, mime_type, model, key, base_url, timeout, language):
    """Qwen-Audio uses the native HTTP API, not chat/completions."""
    formats = {'audio/wav':'wav', 'audio/x-wav':'wav', 'audio/mpeg':'mp3',
               'audio/mp3':'mp3', 'audio/mp4':'m4a', 'audio/x-m4a':'m4a',
               'audio/aac':'aac', 'audio/ogg':'ogg', 'audio/opus':'opus',
               'audio/flac':'flac', 'audio/webm':'webm', 'audio/3gpp':'3gp'}
    if mime_type not in formats:
        raise ValueError('不支持该录音格式')
    parameters = {'format': formats[mime_type]}
    if parameters['format'] == 'wav':
        with wave.open(io.BytesIO(audio)) as recording:
            parameters['sample_rate'] = str(recording.getframerate())
    if language:
        parameters['language_hints'] = [language]
    payload = {'model':model, 'input':{'messages':[{'role':'user','content':[
        {'type':'input_audio','input_audio':{'data':f'data:{mime_type};base64,' +
         base64.b64encode(audio).decode('ascii')}}]}]}, 'parameters':parameters}
    try:
        with httpx.Client(timeout=httpx.Timeout(timeout, connect=min(5,timeout)),
                          follow_redirects=False) as client:
            response = client.post(_native_endpoint(base_url), json=payload,
                headers={'Authorization':f'Bearer {key}', 'X-DashScope-SSE':'disable'})
    except httpx.TimeoutException as error:
        raise openai.APITimeoutError(request=error.request) from None
    except httpx.RequestError as error:
        raise openai.APIConnectionError(request=error.request) from None
    try:
        body = response.json()
    except ValueError:
        body = {}
    code = body.get('code') if isinstance(body, dict) else None
    if not 200 <= response.status_code < 300 or code:
        error_type = {401:openai.AuthenticationError, 403:openai.PermissionDeniedError,
                      404:openai.NotFoundError, 429:openai.RateLimitError}.get(
                          response.status_code, openai.APIStatusError)
        # Preserve only the error code needed for routing, never the audio/body.
        nested = body.get('error') if isinstance(body, dict) else None
        if not code and isinstance(nested, dict):
            code = nested.get('code')
        raise error_type('语音服务请求未完成', response=response,
                         body={'code':code} if isinstance(code, str) else {}) from None
    output = body.get('output') if isinstance(body, dict) else None
    if not isinstance(output, dict) or not isinstance(output.get('text'), str):
        raise RuntimeError('语音服务返回格式异常')
    return output['text']


def transcribe_bytes(audio: bytes, mime_type: str, *, timeout: float = 25,
                     language: str | None = None) -> str:
    """Both providers share one timeout budget; no chat or health-record writes."""
    key = os.getenv('ASR_API_KEY') or DASHSCOPE_API_KEY
    if not key:
        raise RuntimeError('服务端未配置语音转写凭据')
    base_url = os.getenv('ASR_BASE_URL', LLM_BASE_URL)
    deadline = time.monotonic() + timeout

    def request(model):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise openai.APITimeoutError(request=httpx.Request('POST', base_url))
        adapter = _native_transcription if model.startswith('qwen-audio-') else _compatible_transcription
        result = adapter(audio, mime_type, model, key, base_url, remaining, language)
        if not isinstance(result, str):
            raise RuntimeError('语音服务返回格式异常')
        text = result.strip()
        if not text:
            raise ValueError('没有识别到文字，请确认录音中有清晰讲话')
        if len(text)>5000:
            raise RuntimeError('语音服务返回内容异常，请重试')
        return text

    return run_with_fallback(os.getenv('ASR_MODEL','qwen3-asr-flash'),
        os.getenv('ASR_FALLBACK_MODEL','qwen-audio-3.1-asr-flash'), request,
        scope=namespace('asr', base_url + '|' + os.getenv('ASR_NATIVE_BASE_URL',''), key))


def transcribe_audio(path: Path, mime_type: str) -> str:
    # Preserve the older consultation/family-message callers and their timeout.
    return transcribe_bytes(path.read_bytes(),mime_type,timeout=90)

"""Small bounded transcription executor; no persistence or implicit chat calls."""
import threading
from concurrent.futures import ThreadPoolExecutor,TimeoutError as FutureTimeout

import openai
from core.speech_input import normalize_audio,AudioInputError
from core.speech_transcription import transcribe_bytes,asr_configured

REQUEST_TIMEOUT_SECONDS = 35
PROVIDER_TIMEOUT_SECONDS = 25
_slots=threading.BoundedSemaphore(2)
_pool=ThreadPoolExecutor(max_workers=2,thread_name_prefix='speech-transcription')


def _process(data,filename):
    try:
        audio=normalize_audio(data,filename)
        if not asr_configured():
            raise AudioInputError(503,'speech_not_configured','语音转写服务尚未配置，请暂用文字输入')
        try:
            transcript=transcribe_bytes(audio.data,'audio/wav',timeout=PROVIDER_TIMEOUT_SECONDS,language='zh')
        except openai.APITimeoutError:
            raise AudioInputError(504,'transcription_timeout','语音识别超时，请重试或使用文字输入',True) from None
        except (openai.AuthenticationError,openai.PermissionDeniedError,openai.NotFoundError):
            raise AudioInputError(503,'speech_provider_unavailable','语音服务权限或模型配置暂不可用，请暂用文字输入') from None
        except openai.RateLimitError:
            raise AudioInputError(503,'speech_provider_busy','语音服务暂时繁忙，请稍后重试',True) from None
        except openai.APIError:
            raise AudioInputError(502,'speech_provider_error','语音服务连接失败，请重试或使用文字输入',True) from None
        except ValueError:
            raise AudioInputError(422,'no_speech','未识别到有效文字，请靠近麦克风重新录音') from None
        except Exception:
            raise AudioInputError(502,'speech_provider_error','语音服务暂不可用，请重试或使用文字输入',True) from None
        return {'transcript':transcript,'duration_seconds':round(audio.duration_seconds,3),
                'requires_confirmation':True,'notice':'语音转写可能有误，请核对文字、数值和药名后再提交。'}
    finally:
        _slots.release()


def transcribe_upload(data,filename):
    if not _slots.acquire(blocking=False):
        raise AudioInputError(429,'speech_busy','正在处理其他录音，请稍后重试',True)
    try:
        future=_pool.submit(_process,data,filename)
    except Exception:
        _slots.release()
        raise AudioInputError(503,'speech_unavailable','语音服务暂不可用，请稍后重试',True) from None
    try:
        return future.result(timeout=REQUEST_TIMEOUT_SECONDS)
    except FutureTimeout:
        # The bounded worker owns cleanup/slot release. A late response is
        # discarded and cannot submit a chat or save a vital.
        raise AudioInputError(504,'transcription_timeout','语音识别超时，请重试或使用文字输入',True) from None

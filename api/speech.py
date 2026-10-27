"""Authenticated short recordings -> editable text, without saving health records."""
import uuid
from typing import Literal

from fastapi import APIRouter,Depends,UploadFile,File,Form
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from core.security import get_current_user
from db.models import User
from core.speech_input import MAX_BYTES,MAX_SECONDS,ffmpeg_path,AudioInputError
from core.speech_transcription import asr_configured
from services.speech_jobs import transcribe_upload,REQUEST_TIMEOUT_SECONDS

router=APIRouter(prefix='/api/speech',tags=['录音转文字'])


class TranscriptionOut(BaseModel):
    transcript:str
    duration_seconds:float
    requires_confirmation:bool
    notice:str
    purpose:Literal['chat','vitals']
    request_id:str


@router.get('/capabilities')
def capabilities(current:User=Depends(get_current_user)):
    return {'max_bytes':MAX_BYTES,'max_duration_seconds':MAX_SECONDS,
            'request_timeout_seconds':REQUEST_TIMEOUT_SECONDS,
            'preferred_format':{'extension':'wav','sample_rate':16000,'channels':1,'encoding':'pcm_s16le'},
            'supported_extensions':['wav','m4a','mp4','3gp','aac','mp3','ogg','opus','flac','webm','mkv'],
            'decoder_available':bool(ffmpeg_path()),'provider_configured':asr_configured(),
            'provider_probe':'not_performed','requires_confirmation':True,
            'note':'配置存在不等于实时服务可用；每次转写以实际响应为准。'}


@router.post('/transcribe',response_model=TranscriptionOut)
def transcribe(file:UploadFile=File(...),purpose:Literal['chat','vitals']=Form('chat'),
               current:User=Depends(get_current_user)):
    request_id=uuid.uuid4().hex
    try:
        data=file.file.read(MAX_BYTES+1)
        if len(data)>MAX_BYTES:
            raise AudioInputError(413,'audio_too_large','录音不能超过8MB，请缩短后重试')
        result=transcribe_upload(data,file.filename or '')
        return {**result,'purpose':purpose,'request_id':request_id}
    except AudioInputError as error:
        headers={'Retry-After':'3'} if error.status==429 else None
        return JSONResponse(status_code=error.status,
            content={'detail':error.detail,'code':error.code,'retryable':error.retryable,'request_id':request_id},
            headers=headers)
    finally:
        file.file.close()

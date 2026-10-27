"""Bounded audio validation/normalization. Temporary files are never public uploads."""
import io
import os
import shutil
import subprocess
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path

MAX_BYTES = 8*1024*1024
MAX_SECONDS = 60
DECODE_TIMEOUT_SECONDS = 8
SAMPLE_RATE = 16000


class AudioInputError(Exception):
    def __init__(self,status,code,detail,retryable=False):
        super().__init__(detail)
        self.status,self.code,self.detail,self.retryable = status,code,detail,retryable


@dataclass
class NormalizedAudio:
    data: bytes
    duration_seconds: float
    source_format: str


def ffmpeg_path():
    configured = os.getenv('FFMPEG_PATH')
    if configured:
        return configured if Path(configured).is_file() else None
    system = shutil.which('ffmpeg')
    if system:
        return system
    try:
        import imageio_ffmpeg
        candidate = imageio_ffmpeg.get_ffmpeg_exe()
        return candidate if Path(candidate).is_file() else None
    except (ImportError,RuntimeError,OSError):
        return None


def identify(data,filename):
    ext = Path(filename or '').suffix.lower()
    if data[:4]==b'RIFF' and data[8:12]==b'WAVE':kind,extensions='wav',{'.wav'}
    elif data[:4]==b'OggS':kind,extensions='ogg',{'.ogg','.opus'}
    elif data[:4]==b'fLaC':kind,extensions='flac',{'.flac'}
    elif data[4:8]==b'ftyp':kind,extensions='mov',{'.m4a','.mp4','.3gp'}
    elif data[:4]==b'\x1aE\xdf\xa3':kind,extensions='matroska',{'.webm','.mkv'}
    elif len(data)>2 and data[0]==255 and data[1]&0xF6==0xF0:kind,extensions='aac',{'.aac'}
    elif data[:3]==b'ID3' or len(data)>2 and data[0]==255 and data[1]&0xE0==0xE0:kind,extensions='mp3',{'.mp3'}
    else:
        raise AudioInputError(415,'unsupported_audio_format','未识别到支持的录音格式，请使用WAV或M4A录音后重试')
    if ext not in extensions:
        raise AudioInputError(415,'audio_extension_mismatch','录音扩展名与实际格式不一致，请重新录音或选择正确的音频文件')
    return kind


def _pcm_wav(data,stream_header=False):
    with wave.open(io.BytesIO(data),'rb') as source:
        if source.getcomptype()!='NONE' or source.getsampwidth()!=2 or source.getnchannels()!=1 or source.getframerate()!=SAMPLE_RATE:
            return None
        claimed=source.getnframes()
        pcm=source.readframes(SAMPLE_RATE*MAX_SECONDS+1)
        if len(pcm)%2:
            raise AudioInputError(422,'invalid_audio','录音文件不完整，请重新录音')
        frames=len(pcm)//2
        if frames>SAMPLE_RATE*MAX_SECONDS:
            raise AudioInputError(422,'audio_too_long','单次录音不能超过60秒，请分段录音')
        if not stream_header and claimed!=frames:
            raise AudioInputError(422,'invalid_audio','录音文件不完整，请重新录音')
        if not pcm or not any(pcm):
            raise AudioInputError(422,'no_speech','录音没有可识别声音，请检查麦克风后重新说话')
    target=io.BytesIO()
    with wave.open(target,'wb') as output:
        output.setnchannels(1);output.setsampwidth(2);output.setframerate(SAMPLE_RATE);output.writeframes(pcm)
    return target.getvalue(),frames/SAMPLE_RATE


def normalize_audio(data: bytes,filename: str) -> NormalizedAudio:
    if not data:
        raise AudioInputError(400,'empty_audio','录音为空，请先录音再上传')
    if len(data)>MAX_BYTES:
        raise AudioInputError(413,'audio_too_large','录音不能超过8MB，请缩短后重试')
    kind=identify(data,filename)
    if kind=='wav':
        try:
            result=_pcm_wav(data)
            if result:
                return NormalizedAudio(*result,source_format=kind)
        except (wave.Error,EOFError):
            raise AudioInputError(422,'invalid_audio','无法读取录音，请重新录音') from None
    executable=ffmpeg_path()
    if not executable:
        raise AudioInputError(503,'audio_decoder_unavailable','录音转换服务暂不可用，可改用16kHz单声道PCM WAV或稍后重试',True)
    root=Path(os.getenv('SPEECH_TEMP_DIR',str(Path(__file__).resolve().parents[2]/'.speech_tmp')))
    root.mkdir(parents=True,exist_ok=True)
    # A fixed demuxer and protocol list reject playlists and external network
    # sources. The supplied filename is never used as a filesystem path.
    with tempfile.TemporaryDirectory(prefix='asr-',dir=root) as directory:
        path=Path(directory)/'input.audio';path.write_bytes(data)
        command=[executable,'-nostdin','-hide_banner','-loglevel','error','-protocol_whitelist','file,pipe',
                 '-format_whitelist',kind,'-f',kind]
        if kind=='mov':
            command+=['-enable_drefs','0','-use_absolute_path','0']
        command+=['-i',str(path),'-map','0:a:0','-vn','-sn','-dn','-ac','1','-ar',str(SAMPLE_RATE),
                  '-c:a','pcm_s16le','-t',str(MAX_SECONDS+1),'-f','wav','pipe:1']
        try:
            converted=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                                     timeout=DECODE_TIMEOUT_SECONDS,check=False)
        except subprocess.TimeoutExpired:
            raise AudioInputError(422,'audio_decode_timeout','录音转换超时，请缩短录音后重试') from None
        except OSError:
            raise AudioInputError(503,'audio_decoder_unavailable','录音转换服务暂不可用，请稍后重试',True) from None
        if converted.returncode or len(converted.stdout)>2*SAMPLE_RATE*(MAX_SECONDS+2)+4096:
            raise AudioInputError(422,'invalid_audio','录音损坏或没有音轨，请重新录音')
        try:
            result=_pcm_wav(converted.stdout,stream_header=True)
        except (wave.Error,EOFError):
            raise AudioInputError(422,'invalid_audio','录音转换失败，请重新录音') from None
        if result is None:
            raise AudioInputError(422,'invalid_audio','录音转换失败，请重新录音')
        return NormalizedAudio(*result,source_format=kind)

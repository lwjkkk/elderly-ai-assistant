"""Real decoder/HTTP/JWT/SQLite. ASR is explicitly stubbed here; live ASR is separate."""
import sys,io,wave,math,struct,tempfile,subprocess,threading,time,unittest
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch,MagicMock
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
import httpx,openai
from sqlalchemy import create_engine,select,func
from sqlalchemy.orm import sessionmaker
from fastapi import FastAPI
from fastapi.testclient import TestClient
from db.database import Base,get_db
from db.models import User
from core.security import create_access_token
from core import speech_input as audio,speech_transcription as provider
from services import speech_jobs as jobs
from api import speech

def wav(seconds=1,rate=16000,channels=1,silent=False):
 pcm=b'\0\0'*int(seconds*rate)*channels if silent else b''.join(
  struct.pack('<h',int(math.sin(i*2*math.pi*440/rate)*2000))*channels for i in range(int(seconds*rate)))
 b=io.BytesIO()
 with wave.open(b,'wb') as f:f.setnchannels(channels);f.setsampwidth(2);f.setframerate(rate);f.writeframes(pcm)
 return b.getvalue()

class Input(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='speech-input-',dir=Path(__file__).parent)
  self.env=patch.dict('os.environ',{'SPEECH_TEMP_DIR':str(Path(self.temp.name)/'private')});self.env.start()
 def tearDown(self):self.env.stop();self.temp.cleanup()
 def test_pcm_wav_needs_no_decoder(self):
  with patch.object(audio,'ffmpeg_path',return_value=None):result=audio.normalize_audio(wav(),'x.wav')
  self.assertEqual(result.duration_seconds,1)
  with wave.open(io.BytesIO(result.data)) as f:self.assertEqual((f.getnchannels(),f.getsampwidth(),f.getframerate(),f.getnframes()),(1,2,16000,16000))
 def test_stereo_48khz_is_really_normalized(self):
  result=audio.normalize_audio(wav(rate=48000,channels=2),'x.wav')
  with wave.open(io.BytesIO(result.data)) as f:self.assertEqual((f.getnchannels(),f.getframerate()),(1,16000))
 def test_real_m4a_ogg_mp3_flac_decode_and_cleanup(self):
  source=Path(self.temp.name)/'source.wav';source.write_bytes(wav())
  for ext,codec in [('m4a','aac'),('ogg','libopus'),('mp3','libmp3lame'),('flac','flac')]:
   target=Path(self.temp.name)/('encoded.'+ext)
   subprocess.run([audio.ffmpeg_path(),'-nostdin','-v','error','-y','-i',str(source),'-c:a',codec,str(target)],check=True)
   normalized=audio.normalize_audio(target.read_bytes(),target.name)
   self.assertAlmostEqual(normalized.duration_seconds,1,delta=.1)
   self.assertEqual(list((Path(self.temp.name)/'private').iterdir()),[])
 def test_decode_failure_cleans_private_file(self):
  with self.assertRaises(audio.AudioInputError):audio.normalize_audio(b'\0\0\0\x18ftypM4A '+b'garbage'*10,'x.m4a')
  self.assertEqual(list((Path(self.temp.name)/'private').iterdir()),[])
 def test_empty_rejected(self):
  with self.assertRaises(audio.AudioInputError) as error:audio.normalize_audio(b'','x.wav')
  self.assertEqual(error.exception.code,'empty_audio')
 def test_silence_not_sent_as_speech(self):
  with self.assertRaises(audio.AudioInputError) as error:audio.normalize_audio(wav(silent=True),'x.wav')
  self.assertEqual(error.exception.code,'no_speech')
 def test_exact_60_seconds_accepted(self):self.assertEqual(audio.normalize_audio(wav(60),'x.wav').duration_seconds,60)
 def test_one_frame_over_60_rejected(self):
  with self.assertRaises(audio.AudioInputError) as error:audio.normalize_audio(wav(60+1/16000),'x.wav')
  self.assertEqual(error.exception.code,'audio_too_long')
 def test_oversize_rejected(self):
  with self.assertRaises(audio.AudioInputError) as error:audio.normalize_audio(b'x'*(audio.MAX_BYTES+1),'x.wav')
  self.assertEqual(error.exception.status,413)
 def test_extension_does_not_override_content(self):
  with self.assertRaises(audio.AudioInputError) as error:audio.normalize_audio(wav(),'x.m4a')
  self.assertEqual(error.exception.code,'audio_extension_mismatch')
 def test_fake_audio_and_playlists_rejected(self):
  for body in [b'<html>not audio</html>',b'#EXTM3U\nhttps://example.invalid/audio.mp3',b'file:///etc/passwd']:
   with self.assertRaises(audio.AudioInputError):audio.normalize_audio(body,'x.mp3')
 def test_truncated_pcm_rejected(self):
  with self.assertRaises(audio.AudioInputError):audio.normalize_audio(wav()[:-5],'x.wav')
 def test_file_name_is_not_used_as_disk_path(self):
  self.assertEqual(audio.normalize_audio(wav(),'../../outside.wav').duration_seconds,1)
  self.assertFalse((Path(self.temp.name).parent/'outside.wav').exists())
 def test_missing_decoder_is_explicit(self):
  with patch.object(audio,'ffmpeg_path',return_value=None):
   with self.assertRaises(audio.AudioInputError) as error:audio.normalize_audio(wav(rate=48000),'x.wav')
  self.assertEqual(error.exception.code,'audio_decoder_unavailable')
 def test_decoder_timeout_cleans_private_file(self):
  with patch.object(audio.subprocess,'run',side_effect=subprocess.TimeoutExpired('ffmpeg',8)):
   with self.assertRaises(audio.AudioInputError) as error:audio.normalize_audio(wav(rate=48000),'x.wav')
  self.assertEqual(error.exception.code,'audio_decode_timeout');self.assertEqual(list((Path(self.temp.name)/'private').iterdir()),[])

class HTTP(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='speech-http-',dir=Path(__file__).parent)
  self.engine=create_engine('sqlite:///'+str(Path(self.temp.name)/'auth.db'),connect_args={'check_same_thread':False})
  Base.metadata.create_all(self.engine);self.sessions=sessionmaker(bind=self.engine)
  with self.sessions() as db:
   user=User(id=1,role='elder',phone='synthetic',password_hash='x',nickname='fixture',birth_ym='1950-01');db.add(user);db.commit();self.token=create_access_token(user)
  app=FastAPI();app.include_router(speech.router)
  def database():
   with self.sessions() as db:yield db
  app.dependency_overrides[get_db]=database;self.app=app;self.client=TestClient(app)
  self.asr_patch=patch.object(jobs,'transcribe_bytes',return_value='我的血压高压145，低压90。');self.asr=self.asr_patch.start()
  self.cfg=patch.object(jobs,'asr_configured',return_value=True);self.cfg.start()
 def tearDown(self):self.client.close();self.asr_patch.stop();self.cfg.stop();self.engine.dispose();self.temp.cleanup()
 def post(self,body=None,name='x.wav',purpose='chat',auth=True):
  return self.client.post('/api/speech/transcribe',data={'purpose':purpose},files={'file':(name,wav() if body is None else body,'application/octet-stream')},headers={'Authorization':'Bearer '+self.token} if auth else {})
 def snapshot(self):
  with self.engine.connect() as conn:return {table.name:conn.execute(select(func.count()).select_from(table)).scalar() for table in Base.metadata.tables.values()}
 def test_authenticated_upload_returns_editable_text(self):
  result=self.post();self.assertEqual(result.status_code,200,result.text);data=result.json();self.assertEqual(data['transcript'],'我的血压高压145，低压90。');self.assertTrue(data['requires_confirmation']);self.assertEqual(data['duration_seconds'],1);self.assertTrue(data['request_id'])
 def test_purposes_have_no_database_side_effects(self):
  before=self.snapshot()
  for purpose in ['chat','vitals']:self.assertEqual(self.post(purpose=purpose).status_code,200)
  self.assertEqual(self.snapshot(),before)
 def test_unauthenticated_never_calls_asr(self):self.assertEqual(self.post(auth=False).status_code,401);self.asr.assert_not_called()
 def test_invalid_token_never_calls_asr(self):
  r=self.client.post('/api/speech/transcribe',headers={'Authorization':'Bearer invalid'},files={'file':('x.wav',wav())});self.assertEqual(r.status_code,401);self.asr.assert_not_called()
 def test_oversize_blocked_before_asr(self):self.assertEqual(self.post(b'x'*(audio.MAX_BYTES+1)).status_code,413);self.asr.assert_not_called()
 def test_empty_blocked_before_asr(self):self.assertEqual(self.post(b'').json()['code'],'empty_audio');self.asr.assert_not_called()
 def test_silence_blocked_before_asr(self):self.assertEqual(self.post(wav(silent=True)).json()['code'],'no_speech');self.asr.assert_not_called()
 def test_unknown_extension_blocked(self):self.assertEqual(self.post(name='x.exe').status_code,415);self.asr.assert_not_called()
 def test_missing_file_and_invalid_purpose_are_validation_errors(self):
  self.assertEqual(self.client.post('/api/speech/transcribe',headers={'Authorization':'Bearer '+self.token}).status_code,422)
  self.assertEqual(self.post(purpose='unknown').status_code,422)
 def test_missing_configuration_explicit(self):
  with patch.object(jobs,'asr_configured',return_value=False):r=self.post()
  self.assertEqual(r.status_code,503);self.assertEqual(r.json()['code'],'speech_not_configured');self.asr.assert_not_called()
 def test_provider_empty_result_is_not_success(self):
  self.asr.side_effect=ValueError('empty');r=self.post();self.assertEqual(r.status_code,422);self.assertEqual(r.json()['code'],'no_speech')
 def test_provider_timeout(self):
  self.asr.side_effect=openai.APITimeoutError(request=httpx.Request('POST','https://test.invalid'));r=self.post();self.assertEqual(r.status_code,504);self.assertTrue(r.json()['retryable'])
 def test_provider_auth_and_model_error_not_login_error(self):
  for error,status in [(openai.AuthenticationError,401),(openai.PermissionDeniedError,403),(openai.NotFoundError,404)]:
   response=httpx.Response(status,request=httpx.Request('POST','https://test.invalid'))
   self.asr.side_effect=error('secret-upstream',response=response,body={});r=self.post();self.assertEqual(r.status_code,503);self.assertNotIn('secret-upstream',r.text)
 def test_provider_rate_limit(self):
  response=httpx.Response(429,request=httpx.Request('POST','https://test.invalid'))
  self.asr.side_effect=openai.RateLimitError('quota',response=response,body={});r=self.post();self.assertEqual(r.status_code,503);self.assertTrue(r.json()['retryable'])
 def test_provider_connection_failure(self):
  self.asr.side_effect=openai.APIConnectionError(request=httpx.Request('POST','https://test.invalid'));r=self.post();self.assertEqual(r.status_code,502);self.assertTrue(r.json()['retryable'])
 def test_unexpected_error_does_not_leak_secrets(self):
  self.asr.side_effect=RuntimeError('sk-synthetic-credential');r=self.post();self.assertEqual(r.status_code,502);self.assertNotIn('sk-synthetic',r.text)
 def test_capacity_limit_returns_429_without_queued_work(self):
  release=threading.Event();entered=[threading.Event(),threading.Event()];counter=[0];lock=threading.Lock()
  def blocked(*a,**kw):
   with lock:i=counter[0];counter[0]+=1
   entered[i].set();release.wait(3);return '测试文字'
  try:
   self.asr.side_effect=blocked
   with ThreadPoolExecutor(max_workers=2) as pool:
    first=pool.submit(self.post);second=pool.submit(self.post)
    self.assertTrue(all(e.wait(2) for e in entered))
    third=self.post();self.assertEqual(third.status_code,429);self.assertEqual(third.headers['Retry-After'],'3')
    release.set();self.assertEqual(first.result().status_code,200);self.assertEqual(second.result().status_code,200)
  finally:release.set()
 def test_wall_timeout_late_result_has_no_side_effects(self):
  release=threading.Event()
  def late(*a,**kw):release.wait(2);return '迟到文字'
  before=self.snapshot()
  try:
   self.asr.side_effect=late
   with patch.object(jobs,'REQUEST_TIMEOUT_SECONDS',.03):
    started=time.perf_counter();r=self.post();self.assertLess(time.perf_counter()-started,.5);self.assertEqual(r.status_code,504)
  finally:release.set();time.sleep(.04)
  self.assertEqual(self.snapshot(),before)
 def test_upload_file_is_closed_even_after_error(self):
  from starlette.datastructures import UploadFile
  file=UploadFile(filename='x.wav',file=io.BytesIO(b''))
  result=speech.transcribe(file=file,purpose='chat',current=User(id=1));self.assertEqual(result.status_code,400);self.assertTrue(file.file.closed)
 def test_capabilities_does_not_claim_live_verification(self):
  r=self.client.get('/api/speech/capabilities',headers={'Authorization':'Bearer '+self.token});self.assertEqual(r.status_code,200);data=r.json();self.assertEqual(data['max_duration_seconds'],60);self.assertEqual(data['provider_probe'],'not_performed');self.assertTrue(data['requires_confirmation'])
 def test_provider_receives_only_canonical_audio_and_no_extra_health_fields(self):
  self.post(purpose='vitals');args,kwargs=self.asr.call_args
  self.assertEqual(args[1],'audio/wav');self.assertEqual(kwargs,{'timeout':25,'language':'zh'})
  with wave.open(io.BytesIO(args[0])) as f:self.assertEqual((f.getframerate(),f.getnchannels(),f.getsampwidth()),(16000,1,2))
 def test_openapi_documents_success_and_upload(self):
  schema=self.client.get('/openapi.json').json();self.assertIn('TranscriptionOut',schema['components']['schemas']);self.assertIn('multipart/form-data',schema['paths']['/api/speech/transcribe']['post']['requestBody']['content'])

class Provider(unittest.TestCase):
 def test_actual_request_shape_and_client_closed(self):
  client=MagicMock();client.__enter__.return_value=client
  client.chat.completions.create.return_value=SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content='识别文字'))])
  with patch.object(provider,'OpenAI',return_value=client) as factory,patch.object(provider,'DASHSCOPE_API_KEY','synthetic-key'):
   self.assertEqual(provider.transcribe_bytes(wav(),'audio/wav',timeout=25,language='zh'),'识别文字')
  self.assertEqual(factory.call_args.kwargs['max_retries'],0);client.__exit__.assert_called_once()
  call=client.chat.completions.create.call_args.kwargs;self.assertEqual(call['extra_body'],{'asr_options':{'enable_itn':True,'language':'zh'}})
  self.assertTrue(call['messages'][0]['content'][0]['input_audio']['data'].startswith('data:audio/wav;base64,'))
 def test_legacy_file_wrapper_keeps_timeout(self):
  with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as directory:
   path=Path(directory)/'x.wav';path.write_bytes(wav())
   with patch.object(provider,'transcribe_bytes',return_value='旧接口文字') as call:self.assertEqual(provider.transcribe_audio(path,'audio/wav'),'旧接口文字')
   self.assertEqual(call.call_args.kwargs,{'timeout':90})

if __name__=='__main__':unittest.main(verbosity=2)

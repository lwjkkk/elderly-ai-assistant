"""家人媒体消息必须持久化；录音和转写仅绑定双方可访问。"""
import base64
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from api import messages, users, vitals, reports, consults
from core.security import get_current_user
from db.database import Base, get_db
from db.models import User, FamilyBinding, Vitals, HealthReport, ConsultRecord


class FamilyMediaTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://', connect_args={'check_same_thread': False},
                                    poolclass=StaticPool)
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()
        for i, role in [(1, 'elder'), (2, 'family'), (3, 'family')]:
            self.db.add(User(id=i, role=role, phone=f'1380000000{i}',
                             nickname=f'user{i}', password_hash='unused',
                             birth_ym='1970-01' if role == 'elder' else None))
        self.db.add(FamilyBinding(id=1, elder_id=1, family_id=2,
                                  status='active', invite_code='test'))
        self.db.commit()
        self.current_id = 1
        app = FastAPI()
        app.include_router(messages.router)
        for router in [users.router, vitals.router, reports.router, consults.router]:
            app.include_router(router)
        def database():
            yield self.db
        app.dependency_overrides[get_db] = database
        app.dependency_overrides[get_current_user] = lambda: self.db.get(User, self.current_id)
        self.client = TestClient(app)
        self.directory = tempfile.TemporaryDirectory()
        self.media = patch.object(messages, 'MEDIA_DIR', Path(self.directory.name))
        self.media.start()
        self.file_patches = []
        for module, attr in [(users, 'AVATAR_DIR'), (reports, 'UPLOAD_DIR'), (consults, 'UPLOAD_DIR')]:
            replacement = patch.object(module, attr, self.directory.name)
            replacement.start()
            self.file_patches.append(replacement)

    def tearDown(self):
        self.client.close()
        self.db.close()
        self.engine.dispose()
        self.media.stop()
        for replacement in self.file_patches:
            replacement.stop()
        self.directory.cleanup()

    def test_consult_summary_is_generated_persisted_and_bound(self):
        with patch('core.consult_summary.SessionLocal', sessionmaker(bind=self.engine)), \
             patch('core.speech_transcription.transcribe_audio', return_value='医生说注意休息') as asr, \
             patch('core.qwen_llm.call_qwen', return_value='医生交代：注意休息') as llm:
            response = self.client.post('/api/consults/upload',
                files={'file': ('visit.m4a', b'audio', 'audio/mp4')})
            self.assertEqual(response.status_code, 200, response.text)
            record_id = response.json()['id']
            self.db.expire_all()
            url = f'/api/consults/{record_id}/summary'
            data = self.client.get(url).json()
            self.assertEqual(data['summary_status'], 'ready')
            self.assertEqual(data['summary'], '医生交代：注意休息')
            self.assertEqual(data['transcript'], '医生说注意休息')
            self.current_id = 2
            self.assertEqual(self.client.get(url).status_code, 200)
            self.client.post(f'/api/consults/{record_id}/summarize')
            asr.assert_called_once()
            llm.assert_called_once()
            self.current_id = 3
            self.assertEqual(self.client.get(url).status_code, 403)
            self.assertEqual(self.client.post(f'/api/consults/{record_id}/summarize').status_code, 403)

    def test_consult_summary_failure_and_historical_retry(self):
        record = ConsultRecord(elder_id=1, audio_url='/api/consults/audio/old.m4a')
        self.db.add(record)
        self.db.commit()
        (Path(self.directory.name) / 'old.m4a').write_bytes(b'audio')
        url = f'/api/consults/{record.id}/summarize'
        with patch('core.consult_summary.SessionLocal', sessionmaker(bind=self.engine)), \
             patch('core.speech_transcription.transcribe_audio', side_effect=RuntimeError('offline')):
            self.assertEqual(self.client.post(url).status_code, 200)
        self.db.expire_all()
        self.assertEqual(self.db.get(ConsultRecord, record.id).summary_status, 'failed')
        with patch('core.consult_summary.SessionLocal', sessionmaker(bind=self.engine)), \
             patch('core.speech_transcription.transcribe_audio', return_value='清晰录音'), \
             patch('core.qwen_llm.call_qwen', return_value='主要诉求：咨询'):
            self.assertEqual(self.client.post(url).status_code, 200)
        self.db.expire_all()
        self.assertEqual(self.db.get(ConsultRecord, record.id).summary_status, 'ready')

    def upload(self):
        return self.client.post('/api/messages/1/audio',
            files={'file': ('voice.m4a', b'test-audio-data', 'audio/mp4')},
            data={'duration': '3', 'client_id': 'voice-1'})

    def test_recording_survives_sync_and_retry_and_is_private(self):
        response = self.upload()
        self.assertEqual(response.status_code, 200, response.text)
        row = response.json()
        self.assertEqual(self.upload().json()['id'], row['id'])
        self.assertEqual(len(self.client.get('/api/messages/1').json()), 1)
        url = row['content']['text']
        self.current_id = 2
        self.assertEqual(self.client.get(url).content, b'test-audio-data')
        self.assertEqual(self.client.delete(f'/api/messages/1/{row["id"]}').status_code, 403)
        self.current_id = 3
        self.assertEqual(self.client.get(url).status_code, 403)
        self.assertEqual(self.client.post(f'/api/messages/1/{row["id"]}/transcribe').status_code, 403)
        self.current_id = 1
        self.assertEqual(self.client.delete(f'/api/messages/1/{row["id"]}').status_code, 200)
        self.assertEqual(list(Path(self.directory.name).iterdir()), [])
        self.assertEqual(self.client.get('/api/messages/1').json(), [])

    def test_transcript_is_cached_and_image_is_persisted(self):
        row = self.upload().json()
        url = f'/api/messages/1/{row["id"]}/transcribe'
        with patch('core.speech_transcription.transcribe_audio', return_value='你好，记得吃药') as asr:
            self.assertEqual(self.client.post(url).json()['text'], '你好，记得吃药')
            self.current_id = 2
            self.assertEqual(self.client.post(url).json()['text'], '你好，记得吃药')
            asr.assert_called_once()
        self.current_id = 1
        result = self.client.post('/api/messages/1', json={'kind': 'image', 'content': {
            'image': base64.b64encode(b'picture').decode(), 'client_id': 'image-1'}})
        self.assertEqual(result.status_code, 200)
        synced = self.client.get('/api/messages/1').json()
        self.assertEqual(len(synced), 2)
        self.assertEqual(synced[0]['content']['transcript'], '你好，记得吃药')
        self.assertEqual(synced[1]['kind'], 'image')

    def test_uploaded_records_can_only_be_deleted_by_owner(self):
        self.db.add(Vitals(id=1, elder_id=1, type='hr', value='70'))
        self.db.add(HealthReport(id=1, elder_id=1, image_url='/api/reports/image/report.jpg'))
        self.db.add(ConsultRecord(id=1, elder_id=1, audio_url='/api/consults/audio/consult.m4a'))
        self.db.get(User, 1).avatar_url = '/api/users/avatar/avatar.jpg'
        self.db.commit()
        for filename in ['report.jpg', 'consult.m4a', 'avatar.jpg']:
            Path(self.directory.name, filename).write_bytes(b'test')
        self.current_id = 2
        for url in ['/api/vitals/1', '/api/reports/1', '/api/consults/1']:
            self.assertEqual(self.client.delete(url).status_code, 403)
        self.current_id = 1
        for url in ['/api/vitals/1', '/api/reports/1', '/api/consults/1', '/api/users/avatar']:
            response = self.client.delete(url)
            self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(list(Path(self.directory.name).iterdir()), [])
        self.assertIsNone(self.db.get(User, 1).avatar_url)


if __name__ == '__main__':
    unittest.main()

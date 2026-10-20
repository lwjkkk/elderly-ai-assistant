"""Run: .venv/Scripts/python.exe -m unittest backend_validation.test_regressions -v.

Uses an isolated in-memory database and temporary uploads; no live user data.
OCR/AI are replaced for business tests. PDF generation uses real dependencies.
"""
import base64
import io
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from api import auth, consults, drugs, meds, messages, privacy, reports, routes, sync, vitals
from core import chat_summary, consult_summary, health_llm, ocr
from core.report_parse import parse_metrics
from core.security import create_access_token
from db.database import Base, get_db
from db.models import User, FamilyBinding, ChatSummary, DrugQuery, MedicationLog
from services import scheduler


class BackendRegressions(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
        Base.metadata.create_all(self.engine)
        self.sessions = sessionmaker(bind=self.engine)
        with self.sessions() as db:
            # 10.26 年龄分层闸门要求老人有 birth_ym：
            #   id=1 younger（1970年生），默认 sync=True，家属 2 访问放行；
            #   id=3 younger，家属 2 未绑定 → 403。
            #   senior 强制分享场景由 test_age_tier.py 单独覆盖。
            db.add_all([
                User(id=1, role='elder', phone='1', nickname='e1', password_hash='test',
                     birth_ym='1970-05', sync_summary_to_family=True),
                User(id=2, role='family', phone='2', nickname='f2', password_hash='test'),
                User(id=3, role='elder', phone='3', nickname='e3', password_hash='test',
                     birth_ym='1970-05', sync_summary_to_family=True),
                User(id=4, role='family', phone='4', nickname='f4', password_hash='test'),
            ])
            db.add(FamilyBinding(elder_id=1, family_id=2, status='active', invite_code='TEST01'))
            db.commit()
        app = FastAPI()
        for module in [auth, consults, drugs, meds, messages, privacy, reports, routes, sync, vitals]:
            app.include_router(module.router)
        def db_override():
            with self.sessions() as db:
                yield db
        app.dependency_overrides[get_db] = db_override
        self.client = TestClient(app)
        self.temp = tempfile.TemporaryDirectory()
        for module in [reports, consults]:
            p = patch.object(module, 'UPLOAD_DIR', self.temp.name)
            p.start()
            self.addCleanup(p.stop)
        self.addCleanup(self.client.close)
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.engine.dispose)
        buf = io.BytesIO()
        Image.new('RGB', (100, 40), 'white').save(buf, 'PNG')
        self.png = buf.getvalue()

    def headers(self, user=1):
        with self.sessions() as db:
            return {'Authorization': 'Bearer ' + create_access_token(db.get(User, user))}

    def upload(self, user=1, elder=None):
        data = {} if elder is None else {'elder_id': str(elder)}
        return self.client.post('/api/reports/upload', headers=self.headers(user), data=data,
                                files={'file': ('mobile.bin', self.png, 'application/octet-stream')})

    def test_reference_separators(self):
        for sep in ['--', '-', '~', '～', '至']:
            with self.subTest(sep=sep):
                row = parse_metrics(f'GLU 7.2 mmol/L 3,9{sep}6. 1')[0]
                self.assertEqual((row['lo'], row['hi'], row['status']), (3.9, 6.1, 'high'))
        self.assertEqual(parse_metrics('ALT 52 U/L')[0]['status'], 'unparsed')

    def test_unparsed_and_conflicting_advice(self):
        with patch.object(health_llm, 'call_qwen', return_value='本次没有明显异常'):
            text = health_llm.report_advice('ALT 52 U/L', parse_metrics('ALT 52 U/L'))
        self.assertIn('未能核对', text)
        self.assertIn('已隐藏', text)

    def test_mobile_upload_history_sync_metrics(self):
        with patch.object(reports, 'recognize_image', return_value='GLU 7.2 mmol/L 3.9-6.1'), \
             patch.object(reports, 'report_advice', return_value='需要关注'):
            response = self.upload(user=2)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()['elder_id'], 2)
        self.assertTrue(response.json()['image_url'].endswith('.png'))
        for body in [response.json(), self.client.get('/api/reports', headers=self.headers(2)).json()[0],
                     self.client.get('/api/sync', headers=self.headers(2)).json()['reports'][0]]:
            self.assertEqual(body['metrics'][0]['status'], 'high')

    def test_invalid_upload_and_server_failure(self):
        bad = self.client.post('/api/reports/upload', headers=self.headers(),
                               files={'file': ('fake.jpg', b'not an image', 'image/jpeg')})
        self.assertEqual(bad.status_code, 400)
        for exception, status in [(ocr.OcrUnavailableError('broken engine'), 500),
                                  (ocr.OcrNoTextError('no text'), 400)]:
            with patch.object(reports, 'recognize_image', side_effect=exception):
                response = self.upload()
            self.assertEqual(response.status_code, status, response.text)
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])

    def test_ocr_error_status_all_routes(self):
        # 10.23 起 /api/vitals/recognize 拍照体征入口已删除，仅保留 drugs 体检报告识别
        for module, endpoint in [(drugs, '/api/drugs/query')]:
            for exc, status in [(ocr.OcrUnavailableError('broken'), 500), (ocr.OcrNoTextError('no text'), 400)]:
                with self.subTest(endpoint=endpoint, status=status), \
                     patch.object(module, 'recognize_image', side_effect=exc), \
                     patch.object(module, 'call_qwen') as llm:
                    response = self.client.post(endpoint, json={'image_base64': 'dummy'}, headers=self.headers())
                    self.assertEqual(response.status_code, status)
                    llm.assert_not_called()

    def test_photo_vitals_route_removed(self):
        # 拍照体征识别入口已删除，调用应返回 404；体检报告 OCR 仍正常
        response = self.client.post('/api/vitals/recognize', json={'image_base64': 'dummy'}, headers=self.headers())
        self.assertIn(response.status_code, (404, 405), response.text)

    def test_units_and_implausible_vitals(self):
        result = vitals._parse_vitals_llm('TYPE: bs\nVALUE: 126\nUNIT: mg/dL', None)
        self.assertEqual((result['value'], result['unit']), (7.0, 'mmol/L'))
        for text in ['TYPE: bp\nSYSTOLIC: 50\nDIASTOLIC: 90', 'TYPE: hr\nVALUE: -1',
                     'TYPE: bs\nVALUE: 500', 'TYPE: weight\nVALUE: 900']:
            self.assertIsNone(vitals._parse_vitals_llm(text, None))

    def test_family_ownership_and_bound_access(self):
        for endpoint in ['/api/vitals', '/api/reports', '/api/consults', '/api/meds', '/api/sync']:
            with self.subTest(endpoint=endpoint):
                self.assertEqual(self.client.get(endpoint, headers=self.headers(2)).status_code, 200)
                self.assertEqual(self.client.get(endpoint, params={'elder_id': 1}, headers=self.headers(2)).status_code, 200)
                self.assertEqual(self.client.get(endpoint, params={'elder_id': 3}, headers=self.headers(2)).status_code, 403)
        response = self.client.post('/api/vitals', json={'type': 'hr', 'value': 72}, headers=self.headers(2))
        self.assertEqual(response.json()['elder_id'], 2)
        self.assertEqual(self.client.get('/api/vitals', headers=self.headers()).json(), [])

    def test_family_personal_audio(self):
        # generate_summary 使用独立的全局 SessionLocal；测试必须把它隔离到内存库，
        # 并 mock 外部 ASR/LLM，避免连接到磁盘真实库或调用外部服务。
        with patch.object(consult_summary, 'SessionLocal', self.sessions), \
             patch('core.speech_transcription.transcribe_audio', return_value='测试转写'), \
             patch('core.qwen_llm.call_qwen', return_value='测试摘要'):
            response = self.client.post('/api/consults/upload', headers=self.headers(2),
                                        files={'file': ('record.m4a', b'test audio', 'application/octet-stream')})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()['elder_id'], 2)

    def new_med(self, start='2026-10-01'):
        response = self.client.post('/api/meds', headers=self.headers(2), json={
            'name': '测试药', 'dosage': '遵医嘱', 'frequency': '每日两次',
            'times': ['08:00', '20:00'], 'start_date': start})
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()['id']

    def test_checkin_schedule_and_ownership(self):
        class Clock(datetime):
            @classmethod
            def now(cls, tz=None):
                return cls(2026, 10, 13, 10, 0, tzinfo=timezone(timedelta(hours=8)))
        med = self.new_med()
        with patch.object(meds, 'datetime', Clock):
            for day, slot, expected in [('2026-10-13', '08:00', 200), ('2026-10-13', '20:00', 400),
                                        ('2026-10-14', '08:00', 400), ('2026-09-30', '08:00', 400),
                                        ('2026-10-13', '09:00', 400)]:
                r = self.client.post('/api/meds/checkin', headers=self.headers(2), json={
                    'medication_id': med, 'date': day, 'slot': slot})
                self.assertEqual(r.status_code, expected, r.text)
        forbidden = self.client.put(f'/api/meds/{med}', headers=self.headers(4), json={'name': 'other'})
        self.assertEqual(forbidden.status_code, 403)

    def test_future_plan_skipped_and_beijing_scheduler(self):
        self.new_med(start='2026-10-14')
        r = self.client.get('/api/meds/today', params={'date': '2026-10-13'}, headers=self.headers(2))
        self.assertEqual(r.json(), [])
        now = datetime(2026, 10, 13, 0, 0, tzinfo=timezone.utc)
        with patch.object(scheduler, 'SessionLocal', self.sessions), patch.object(scheduler.push, 'send_push') as push:
            self.assertEqual(scheduler.run_reminder_cycle(now), [])
            self.assertEqual(scheduler.run_missed_cycle(now + timedelta(hours=2)), [])
            push.assert_not_called()
        self.assertEqual(scheduler._beijing_now(now).hour, 8)
        with self.sessions() as db:
            self.assertEqual(db.query(MedicationLog).count(), 0)

    def test_chat_privacy_owner_and_family(self):
        full_answer = '药品说明。' * 130
        with patch.object(chat_summary, 'SessionLocal', self.sessions), \
             patch.object(chat_summary, '_extract_summary', return_value='查药记录'):
            self.assertTrue(chat_summary.save_summary_sync(1, '这个药有什么作用', full_answer, 'health'))
        with self.sessions() as db:
            db.get(User, 1).sync_summary_to_family = False
            db.add(DrugQuery(elder_id=1, kind='image', explanation='专用查药'))
            db.commit()
            self.assertEqual(db.query(DrugQuery).filter_by(kind='chat').one().explanation, full_answer)
        with patch.object(chat_summary, 'SessionLocal', self.sessions), \
             patch.object(chat_summary, '_extract_summary') as extract:
            self.assertFalse(chat_summary.save_summary_sync(
                1, '隐私开启后的敏感问题', full_answer, 'health'))
            extract.assert_not_called()
        for user, params, chat_count in [(1, {}, 1), (2, {'elder_id': 1}, 0)]:
            r = self.client.get('/api/chat/summaries', headers=self.headers(user), params=params)
            if user == 2 and chat_count == 0:
                # 10.26 年龄闸门：younger 关闭隐私时家属访问返回 403（不再静默空列表）
                self.assertEqual(r.status_code, 403, r.text)
                continue
            self.assertEqual(len(r.json()), chat_count, r.text)
            s = self.client.get('/api/sync', headers=self.headers(user), params=params).json()
            self.assertEqual(len(s['chat_summaries']), chat_count)
            self.assertEqual(len([d for d in s['drug_queries'] if d['kind'] == 'chat']), chat_count)
        r = self.client.get('/api/drugs/records', headers=self.headers(2), params={'elder_id': 1, 'limit': 1})
        # younger 关闭隐私时家属查药记录也被 403
        self.assertEqual(r.status_code, 403, r.text)
        r = self.client.get('/api/drugs/records', headers=self.headers())
        self.assertEqual(next(d['explanation'] for d in r.json() if d['kind'] == 'chat'), full_answer)

    def test_actual_pdf_export(self):
        self.client.post('/api/vitals', json={'type': 'bp', 'systolic': 135, 'diastolic': 85}, headers=self.headers())
        response = self.client.get('/api/vitals/export', headers=self.headers())
        self.assertEqual(response.status_code, 200, response.text[:200])
        self.assertTrue(response.content.startswith(b'%PDF-'))
        Path('backend_validation/sample_vitals.pdf').write_bytes(response.content)

    def test_pdf_empty_invalid_and_missing_dependency(self):
        self.assertEqual(self.client.get('/api/vitals/export', headers=self.headers()).status_code, 400)
        self.client.post('/api/vitals', json={'type': 'hr', 'value': 72}, headers=self.headers())
        with patch.object(vitals, 'generate_vitals_pdf', return_value=b'bad'):
            self.assertEqual(self.client.get('/api/vitals/export', headers=self.headers()).status_code, 500)
        with patch.object(vitals, 'generate_vitals_pdf', side_effect=ModuleNotFoundError('reportlab')):
            self.assertEqual(self.client.get('/api/vitals/export', headers=self.headers()).status_code, 500)

    def test_invalid_base64_is_input_error(self):
        for value in ['', '%%%', base64.b64encode(b'not a picture').decode()]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                ocr._decode_image(value)

    def test_startup_survives_ocr_failure(self):
        import main
        with patch.object(main, 'init_db'), patch.object(main, 'start_scheduler'), \
             patch.object(main, 'verify_ocr_ready', side_effect=ocr.OcrUnavailableError('test failure')), \
             TestClient(main.app) as client:
            self.assertEqual(client.get('/').status_code, 200)
            self.assertFalse(main.app.state.ocr_ready)
            self.assertIn('test failure', main.app.state.ocr_error)

    def test_privacy_enabled_shares_only_bound_account(self):
        with self.sessions() as db:
            db.add(ChatSummary(elder_id=1, category='drug', question='查药', summary='测试', module='health'))
            db.add(DrugQuery(elder_id=1, kind='chat', explanation='测试'))
            db.commit()
        r = self.client.get('/api/sync', params={'elder_id': 1}, headers=self.headers(2))
        self.assertEqual(len(r.json()['chat_summaries']), 1)
        self.assertEqual(len(r.json()['drug_queries']), 1)
        for endpoint in ['/api/sync', '/api/drugs/records', '/api/chat/summaries']:
            self.assertEqual(self.client.get(endpoint, params={'elder_id': 1}, headers=self.headers(4)).status_code, 403)

    def test_bound_family_messages_are_shared_and_persisted(self):
        sent = self.client.post('/api/messages/1', headers=self.headers(1),
                                json={'kind': 'text', 'content': {'text': '记得吃饭'}})
        self.assertEqual(sent.status_code, 200, sent.text)
        received = self.client.get('/api/messages/1', headers=self.headers(2))
        self.assertEqual(received.status_code, 200, received.text)
        self.assertEqual(received.json()[0]['content']['text'], '记得吃饭')
        self.assertEqual(self.client.get('/api/messages/1', headers=self.headers(3)).status_code, 403)

    def test_password_login_returns_user_id(self):
        with patch.object(auth, 'verify_password', return_value=True):
            response = self.client.post('/api/auth/login', json={
                'phone': '1', 'password': 'anything'
            })
        # 测试库手机号为简写，绕过 Pydantic 手机号规则直接验证返回模型。
        if response.status_code == 422:
            with self.sessions() as db:
                db.get(User, 1).phone = '13900000001'
                db.commit()
            with patch.object(auth, 'verify_password', return_value=True):
                response = self.client.post('/api/auth/login', json={
                    'phone': '13900000001', 'password': 'anything'
                })
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()['user_id'], 1)

    def test_vitals_ocr_fallback_extracts_blood_pressure(self):
        parsed = vitals._fallback_parse_ocr('SYS 139 DIA 85 PUL 72', None)
        self.assertEqual((parsed['type'], parsed['systolic'], parsed['diastolic']), ('bp', 139, 85))

    def test_privacy_keeps_records_created_before_enabled_time(self):
        cutoff = datetime.utcnow()
        with self.sessions() as db:
            user = db.get(User, 1)
            user.sync_summary_to_family = False
            user.privacy_enabled_at = cutoff
            db.add(ChatSummary(elder_id=1, category='med', question='旧问题', summary='旧记录',
                               created_at=cutoff - timedelta(minutes=1)))
            db.add(ChatSummary(elder_id=1, category='med', question='新问题', summary='新记录',
                               created_at=cutoff + timedelta(minutes=1)))
            db.commit()
        rows = self.client.get('/api/chat/summaries', params={'elder_id': 1},
                               headers=self.headers(2))
        # 10.26 闸门：younger 关闭隐私时家属 403，不再静默返回空列表
        self.assertEqual(rows.status_code, 403, rows.text)
        # 老人自己访问应能看到旧+新两条（privacy_enabled_at 之后的记录仍对自己可见）
        own = self.client.get('/api/chat/summaries', headers=self.headers(1)).json()
        self.assertEqual(len(own), 2)


if __name__ == '__main__':
    unittest.main(verbosity=2)

"""Real HTTP/SQLite regressions for the October 22 backend contracts.

No model/OCR output is substituted in these business tests. External-failure
injection tests are explicitly named; generative quality is tested separately.
"""
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from api import vitals, messages
from core.security import get_current_user
from core.report_parse import parse_metrics
from db.database import Base, get_db
from db.models import (User, FamilyBinding, Vitals, VitalAlert, FamilyMessage,
                       NotificationOutbox)
from services import push, notification_outbox


class BackendContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.engine = create_engine('sqlite:///' + str(Path(self.temp.name) / 'test.db'),
                                    connect_args={'check_same_thread': False, 'timeout': 15})
        Base.metadata.create_all(self.engine)
        self.sessions = sessionmaker(bind=self.engine)
        with self.sessions() as db:
            db.add_all([
                User(id=1, phone='1', nickname='测试老人', role='elder',
                     password_hash='x', birth_ym='1970-01'),
                User(id=2, phone='2', nickname='测试家属', role='family', password_hash='x'),
                User(id=3, phone='3', nickname='其他老人', role='elder',
                     password_hash='x', birth_ym='1950-01'),
            ])
            db.add(FamilyBinding(id=1, elder_id=1, family_id=2, status='active', invite_code='test'))
            db.commit()
        self.current = 1
        app = FastAPI()
        app.include_router(vitals.router)
        app.include_router(messages.router)
        def database():
            with self.sessions() as db:
                yield db
        def user():
            with self.sessions() as db:
                return db.get(User, self.current)
        app.dependency_overrides[get_db] = database
        app.dependency_overrides[get_current_user] = user
        self.client = TestClient(app)
        self.old_adapter = push.set_adapter(push.MemoryPushAdapter())
        push.clear_sent()

    def tearDown(self):
        self.client.close()
        push.set_adapter(self.old_adapter)
        self.engine.dispose()
        self.temp.cleanup()

    def turn(self, text, session=None):
        data = {'text': text}
        if session:
            data['session_id'] = session
        response = self.client.post('/api/vitals/draft-conversations', json=data)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def ready(self):
        result = self.turn('我的血压150/95，2026-01-01T08:30:00+08:00')
        self.assertTrue(result['can_confirm'], result)
        return result

    def count(self, model):
        with self.sessions() as db:
            return db.query(model).count()

    def test_time_only_followup_and_raw_text(self):
        draft = self.turn('我的血压130/80')
        self.assertIn('measured_at', draft['missing'])
        draft = self.turn('2026-01-01T08:30:00+08:00', draft['session_id'])
        self.assertTrue(draft['can_confirm'], draft)
        self.assertEqual(draft['draft']['measured_at'], '2026-01-01T00:30:00+00:00')
        self.assertIn('我的血压130/80\n2026-', draft['draft']['raw_text'])
        self.assertEqual(self.count(Vitals), 0)

    def test_single_bp_correction_overwrites_previous(self):
        draft = self.ready()
        draft = self.turn('高压改成125', draft['session_id'])
        self.assertEqual(draft['draft']['systolic'], 125)

    def test_object_requires_explicit_confirmation(self):
        draft = self.turn('妈妈血压130/80')
        self.assertFalse(draft['subject_confirmed'])
        draft = self.turn('2026-01-01T08:30:00+08:00', draft['session_id'])
        self.assertFalse(draft['subject_confirmed'])
        draft = self.turn('确认', draft['session_id'])
        self.assertTrue(draft['subject_confirmed'])

    def test_edit_version_time_and_type_cleanup(self):
        draft = self.ready()
        path = f"/api/vitals/draft-conversations/{draft['session_id']}"
        response = self.client.patch(path, json={'version': draft['version'], 'type': 'hr', 'value': 72})
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertIsNone(body['draft']['systolic'])
        self.assertTrue(body['can_confirm'])
        self.assertEqual(self.client.patch(path, json={'version': draft['version'], 'value': 73}).status_code, 409)
        self.assertEqual(self.client.patch(path, json={'version': body['version'], 'measured_at': '2026-02-31T08:00:00+08:00'}).status_code, 400)
        self.assertEqual(self.client.get(path).json()['version'], body['version'])

    def test_confirm_replay_same_id_and_one_notification(self):
        draft = self.ready()
        path = f"/api/vitals/draft-conversations/{draft['session_id']}/confirm"
        first = self.client.post(path, headers={'Idempotency-Key': 'retry'})
        second = self.client.post(path, headers={'Idempotency-Key': 'retry'})
        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(first.json()['id'], second.json()['id'])
        for model in (Vitals, VitalAlert, FamilyMessage, NotificationOutbox):
            self.assertEqual(self.count(model), 1, model.__name__)
        self.assertEqual(first.json()['notification_status'], 'recorded')
        self.assertEqual(len(push.get_sent()), 1)
        other = self.ready()
        conflict = self.client.post(f"/api/vitals/draft-conversations/{other['session_id']}/confirm",
                                    headers={'Idempotency-Key': 'retry'})
        self.assertEqual(conflict.status_code, 409)

    def test_two_concurrent_confirms_one_record(self):
        draft = self.ready()
        path = f"/api/vitals/draft-conversations/{draft['session_id']}/confirm"
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.client.post(path), range(2)))
        self.assertEqual([r.status_code for r in results], [200, 200], [r.text for r in results])
        self.assertEqual(results[0].json()['id'], results[1].json()['id'])
        self.assertEqual(self.count(Vitals), 1)
        self.assertEqual(self.count(FamilyMessage), 1)

    def test_injected_failure_rolls_back_all_writes(self):
        draft = self.ready()
        real = vitals._maybe_create_alert
        def fail_after_stage(db, record):
            real(db, record)
            raise RuntimeError('injected before commit')
        with patch.object(vitals, '_maybe_create_alert', side_effect=fail_after_stage):
            with self.assertRaisesRegex(RuntimeError, 'injected'):
                self.client.post(f"/api/vitals/draft-conversations/{draft['session_id']}/confirm")
        for model in (Vitals, VitalAlert, FamilyMessage, NotificationOutbox):
            self.assertEqual(self.count(model), 0)

    def test_injected_push_failure_preserves_vital_and_retries(self):
        draft = self.ready()
        with patch.object(push, 'send_push', side_effect=RuntimeError('injected provider outage')):
            response = self.client.post(f"/api/vitals/draft-conversations/{draft['session_id']}/confirm")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()['notification_status'], 'failed')
        self.assertEqual(self.count(Vitals), 1)
        outcome = notification_outbox.process_pending(self.sessions)
        self.assertEqual(outcome['recorded'], 1)

    def test_retry_checks_current_sharing_and_binding(self):
        for change in ('privacy', 'unbind'):
            with self.subTest(change=change):
                with self.sessions() as db:
                    db.query(NotificationOutbox).delete()
                    db.get(User, 1).sync_summary_to_family = True
                    db.get(FamilyBinding, 1).status = 'active'
                    db.add(NotificationOutbox(elder_id=1, receiver_id=2, title='test', content='sensitive',
                                               status='failed', channel='in_app', dedupe_key=change))
                    db.commit()
                    if change == 'privacy':
                        db.get(User, 1).sync_summary_to_family = False
                    else:
                        db.get(FamilyBinding, 1).status = 'unbound'
                    db.commit()
                push.clear_sent()
                notification_outbox.process_pending(self.sessions)
                self.assertEqual(push.get_sent(), [])

    def test_message_read_rechecks_privacy(self):
        self.client.post(f"/api/vitals/draft-conversations/{self.ready()['session_id']}/confirm")
        self.current = 2
        self.assertEqual(len(self.client.get('/api/messages/1').json()), 1)
        with self.sessions() as db:
            db.get(User, 1).sync_summary_to_family = False
            db.commit()
        self.assertEqual(self.client.get('/api/messages/1').json(), [])

    def test_cancel_and_confirm_race(self):
        draft = self.ready()
        path = f"/api/vitals/draft-conversations/{draft['session_id']}"
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(self.client.post, path + '/confirm'),
                       pool.submit(self.client.delete, path)]
            results = [f.result() for f in futures]
        state = self.client.get(path).json()['status']
        self.assertIn(state, ('confirmed', 'cancelled'))
        self.assertEqual(self.count(Vitals), int(state == 'confirmed'), [r.text for r in results])

    def test_family_personal_draft_can_be_read_and_confirmed(self):
        self.current = 2
        draft = self.ready()
        path = f"/api/vitals/draft-conversations/{draft['session_id']}"
        self.assertEqual(self.client.get(path).status_code, 200)
        self.assertEqual(self.client.post(path + '/confirm').status_code, 200)

    def test_null_confirmation_rejected_without_server_error(self):
        draft = self.ready()
        response = self.client.patch(f"/api/vitals/draft-conversations/{draft['session_id']}",
            json={'version': draft['version'], 'subject_confirmed': None})
        self.assertEqual(response.status_code, 400, response.text)

    def test_type_switch_and_time_not_used_as_value(self):
        draft = self.ready()
        draft = self.turn('改记心率', draft['session_id'])
        self.assertIsNone(draft['draft']['systolic'])
        self.assertIsNone(draft['draft']['value'])
        draft = self.turn('2026-01-02T09:00:00+08:00', draft['session_id'])
        self.assertIsNone(draft['draft']['value'])
        draft = self.turn('72', draft['session_id'])
        self.assertEqual(draft['draft']['value'], 72)

    def test_afternoon_and_minutes_not_taken_from_vital_value(self):
        from core.vitals_draft import _extract_time
        reference = datetime(2026, 1, 2, 16)
        for spoken, hour, minute in (('昨天下午3点心率50', 15, 0),
                                    ('昨天晚上8点半血糖5.2', 20, 30),
                                    ('昨天早上8点15分血压130/80', 8, 15)):
            with self.subTest(spoken=spoken):
                _, stamp = _extract_time(spoken, reference)
                self.assertEqual((stamp.hour, stamp.minute), (hour, minute))

    def test_outbox_two_workers_claim_once(self):
        with self.sessions() as db:
            db.add(NotificationOutbox(elder_id=1, receiver_id=2, title='test', content='test',
                status='pending', channel='in_app', dedupe_key='race'))
            db.commit()
        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(lambda _: notification_outbox.process_pending(self.sessions), range(2)))
        self.assertEqual(sum(o['recorded'] for o in outcomes), 1)
        self.assertEqual(len(push.get_sent()), 1)

    def test_outbox_recovers_expired_claim_after_restart(self):
        with self.sessions() as db:
            db.add(NotificationOutbox(elder_id=1, receiver_id=2, title='test', content='test',
                status='processing', channel='in_app', dedupe_key='stale',
                claimed_at=datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(minutes=10)))
            db.commit()
        self.assertEqual(notification_outbox.process_pending(self.sessions)['recorded'], 1)

    def test_confirmed_retry_with_concurrent_new_key(self):
        draft = self.ready()
        path = f"/api/vitals/draft-conversations/{draft['session_id']}/confirm"
        first = self.client.post(path).json()
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(lambda _: self.client.post(path, headers={'Idempotency-Key': 'new'}), range(2)))
        self.assertEqual([r.status_code for r in responses], [200, 200])
        self.assertTrue(all(r.json()['id'] == first['id'] for r in responses))

    def test_tiered_legacy_aliases_and_emergency_preserved(self):
        from core import tiered_answer
        from core.agent import _detect_module
        self.assertEqual(_detect_module('老人突然胸闷、喘不过气怎么办？'), 'health')
        parts = tiered_answer.parse_three('【结论】血压偏高。【建议】复测。【就医提醒】持续异常请就医。')
        self.assertEqual(parts['conclusion'], '血压偏高。')
        self.assertEqual(parts['advice'], '复测。')
        self.assertTrue(parts['meaning'])
        with patch.object(tiered_answer, 'call_qwen', side_effect=RuntimeError('injected outage')):
            result = tiered_answer.build('我现在胸闷', '请立即拨打120。', 'elder')
        self.assertEqual(result['source'], 'deterministic')
        for name in ('elder_view', 'family_view'):
            self.assertIn('立即拨打120', result[name]['seek'])
            self.assertTrue(result[name]['conclusion'])

    def test_old_schema_migration_keeps_existing_records(self):
        from sqlalchemy import text, inspect
        from db import database
        old = create_engine('sqlite:///' + str(Path(self.temp.name) / 'old.db'))
        try:
            with old.begin() as connection:
                connection.execute(text('CREATE TABLE vitals (id INTEGER PRIMARY KEY, elder_id INTEGER, type TEXT, systolic INTEGER, diastolic INTEGER, value TEXT, measured_at DATETIME)'))
                connection.execute(text("INSERT INTO vitals VALUES (1, 1, 'bp', 120, 80, NULL, '2026-01-01 00:00:00')"))
            with patch.object(database, 'engine', old):
                database.init_db()
                database.init_db()
            columns = {c['name'] for c in inspect(old).get_columns('notification_outbox')}
            self.assertIn('claimed_at', columns)
            with old.connect() as connection:
                self.assertEqual(connection.execute(text('SELECT systolic FROM vitals WHERE id=1')).scalar(), 120)
                self.assertIsNotNone(connection.execute(text('SELECT created_at FROM vitals WHERE id=1')).scalar())
        finally:
            old.dispose()

    def test_elder_view_keeps_complete_conditional_seek(self):
        from core.tiered_answer import elder_simple
        seek = '如有不适请按医生意见处理。' * 10 + '复测后仍异常请及时就诊。'
        view = elder_simple({'concern': '血压', 'meaning': '需复测', 'next_step': '休息', 'seek': seek})
        self.assertEqual(view['seek'], seek)

    def test_report_blood_pressure_pair_not_replaced_by_diastolic(self):
        row = parse_metrics('血压 120/80 mmHg 90-139/60-89')[0]
        self.assertIsNone(row['result'])
        self.assertEqual(row['result_text'], '120/80')
        self.assertEqual(row['status'], 'unparsed')

    def test_retrieval_focus_filters_wrong_subtopic(self):
        from core.rag_hybrid import _matches_query_focus
        question = '高血压老人平时饮食要注意什么？'
        self.assertFalse(_matches_query_focus(question, '高血压管理', '按医嘱用温水服药，不自行加量。'))
        self.assertFalse(_matches_query_focus(question, '老人节日饮食', '油腻的肉少吃，多吃青菜。'))
        self.assertTrue(_matches_query_focus(question, '高血压管理', '饮食清淡，控制盐摄入。'))
        self.assertFalse(_matches_query_focus('微信怎么发红包', '微信付款码', '不要给陌生人展示付款码。'))
        self.assertFalse(_matches_query_focus('12306怎么买火车票', '车辆年检网上预约', '首页找到机动车检验预约。'))
        self.assertFalse(_matches_query_focus('糖尿病饮食要注意什么', '慢性肾脏病饮食', '合并糖尿病时注意主食。'))

    def test_summary_rechecks_sharing_after_generation(self):
        from core import chat_summary
        from db.models import ChatSummary
        def revoke(*args):
            with self.sessions() as db:
                db.get(User, 1).sync_summary_to_family = False
                db.commit()
            return '回撤期间生成的摘要'
        with patch.object(chat_summary, '_extract_summary', side_effect=revoke):
            result = chat_summary.save_summary_sync(1, '血压偏高', '请复测', 'health',
                                                   session_factory=self.sessions)
        self.assertFalse(result)
        self.assertEqual(self.count(ChatSummary), 0)

    def test_document_and_chunk_metadata_version(self):
        from core.rag_indexer import parse_doc
        path = Path(self.temp.name) / 'example.txt'
        text = '标题：示例\n来源网址：https://example.org/source\n更新时间：2026-01-01\n地区：全国\n回答：\n这是正文。'
        path.write_text(text, encoding='utf-8')
        first = parse_doc(str(path), self.temp.name)
        second = parse_doc(str(path), self.temp.name)
        self.assertEqual(first['document_id'], second['document_id'])
        self.assertEqual(first['document_version'], second['document_version'])
        self.assertEqual(first['source_url'], 'https://example.org/source')
        path.write_text(text + '\n补充内容。', encoding='utf-8')
        third = parse_doc(str(path), self.temp.name)
        self.assertEqual(first['document_id'], third['document_id'])
        self.assertNotEqual(first['document_version'], third['document_version'])

    def test_trend_groups_utc_records_by_shanghai_calendar_day(self):
        with self.sessions() as db:
            db.add(Vitals(elder_id=1, type='hr', value=72,
                          measured_at=datetime(2025, 12, 31, 16, 30)))
            db.commit()
        response = self.client.get('/api/vitals/trend?days=3650')
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()['hr'][0]['date'], '2026-01-01')

    def test_emergency_worker_reads_user_in_its_own_session(self):
        from types import SimpleNamespace
        from core import emergency_alert
        emergency_alert._last_notify.clear()
        # 只传稳定 ID；工作线程必须重新读取当前资料，而非依赖请求 ORM 对象。
        worker = emergency_alert.notify_family_async(
            self.sessions, SimpleNamespace(id=1), '胸痛', ['chest_pain'])
        worker.join(timeout=5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(self.count(FamilyMessage), 1)
        self.assertEqual(self.count(NotificationOutbox), 1)

    def test_no_unit_reversed_ranges_and_two_column_not_normal(self):
        for text in ('GLU 5.0 3.9-6.1', 'GLU 5.0 mmol/L 6.1-3.9',
                     'GLU 5.0 mmol/L 3.9-6.1 ALT 900 U/L 0-40'):
            with self.subTest(text=text):
                rows = parse_metrics(text)
                self.assertTrue(rows)
                self.assertTrue(all(r['status'] == 'unparsed' for r in rows), rows)


if __name__ == '__main__':
    unittest.main()

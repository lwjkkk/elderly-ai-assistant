"""Synthetic local regressions: reported words must not become a different symptom."""
import unittest
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from core.emergency_presentation import category_labels, emergency_metadata
from core.emergency_rules import fast_types


class EmergencyPresentationTests(unittest.TestCase):
    def test_all_risk_groups_preserve_subject_detail_time_negation_and_numbers(self):
        cases = [
            ('chest_pain', '我今天心口像石头压着，但不是胸闷'),
            ('breath', '我妈妈走两步就喘不上气，没有心脏疼'),
            ('consciousness', '刚才晕过去了，现在醒了，持续约10秒'),
            ('stroke', '爸爸左胳膊突然抬不起，右边没事'),
            ('bleeding', '鼻血一直流，不是只有一点血丝'),
            ('choking', '吃饭时喉咙卡住了，说不出话'),
            ('severe_headache', '这次头疼程度8分，和以前轻微头疼不一样'),
            ('severe_allergy', '舌头迅速肿了，吞咽困难，没有皮疹'),
            ('emergency_other', '说不上具体位置，但现在越来越难受'),
        ]
        for key, question in cases:
            with self.subTest(key=key):
                result = emergency_metadata(question, [key])
                self.assertEqual(result['reported_question'], question)
                self.assertTrue(result['emergency_labels'])

    def test_risk_group_never_replaces_reported_words(self):
        for question in ('我心脏疼', '我胸闷', '我心脏疼，没有胸闷', '心脏疼，喘不上气'):
            with self.subTest(question=question):
                metadata = emergency_metadata(question, fast_types(question))
                self.assertEqual(metadata['reported_question'], question)
                self.assertEqual(metadata['emergency_labels'][0], '胸部不适相关危险信号')
                self.assertNotIn('胸闷', '、'.join(metadata['emergency_labels']))
        self.assertEqual(emergency_metadata('微信怎么加好友', []), {})
        self.assertEqual(category_labels(['chest_pain', 'chest_pain']), ['胸部不适相关危险信号'])

    def test_current_negated_historical_and_hypothetical_context(self):
        from core.query_policy import emergency_types
        for question in ('我心脏疼', '心脏痛', '我胸闷', '我心脏疼，没有胸闷'):
            with self.subTest(question=question):
                self.assertIn('chest_pain', emergency_types(question))
        for question in ('我没有心脏疼', '以前心脏疼', '如果心脏疼怎么办', '电影里心脏疼这个词是什么意思'):
            with self.subTest(question=question):
                self.assertEqual(emergency_types(question), [])

    def test_symptom_check_keeps_original_words_in_saved_answer_data(self):
        from api import symptom
        from db.database import Base, get_db
        from db.models import User, SymptomCheck
        from core.security import get_current_user
        engine = create_engine('sqlite://', poolclass=StaticPool,
                               connect_args={'check_same_thread': False})
        sessions = sessionmaker(bind=engine)
        Base.metadata.create_all(engine)
        with sessions() as db:
            db.add(User(id=1, role='elder', phone='synthetic-symptom',
                        nickname='测试长辈', password_hash='test', birth_ym='1950-01'))
            db.commit()
        def local_db():
            with sessions() as db:
                yield db
        def local_user():
            with sessions() as db:
                return db.get(User, 1)
        app = FastAPI()
        app.include_router(symptom.router)
        app.dependency_overrides[get_db] = local_db
        app.dependency_overrides[get_current_user] = local_user
        question = '我心脏疼，没有胸闷，刚才开始的'
        try:
            with TestClient(app) as client:
                response = client.post('/api/symptom-check', json={'input_text': question})
                self.assertEqual(response.status_code, 200, response.text)
                result = response.json()
                self.assertEqual(result['input_text'], question)
                self.assertEqual(result['risk'], 'red')
                self.assertNotIn('胸闷', result['advice_text'])
            with sessions() as db:
                saved = db.query(SymptomCheck).one()
                self.assertEqual(saved.answer_data['reported_question'], question)
                self.assertEqual(saved.answer_data['emergency_labels'], ['胸部不适相关危险信号'])
        finally:
            engine.dispose()

    def test_chat_and_both_views_keep_original_question_and_120(self):
        from api import routes
        from db.database import get_db
        from core.security import get_optional_user
        from core.query_policy import decision
        engine = create_engine('sqlite://', poolclass=StaticPool,
                               connect_args={'check_same_thread': False})
        sessions = sessionmaker(bind=engine)
        app = FastAPI()
        app.include_router(routes.router)
        def local_db():
            with sessions() as db:
                yield db
        app.dependency_overrides[get_db] = local_db
        app.dependency_overrides[get_optional_user] = lambda: None
        def local_answer(question, **kwargs):
            policy = decision(question)
            return {**policy, 'answer_origin': 'safety_rule', 'sources': [], 'steps': []}
        try:
            with patch.object(routes, 'get_agent_answer', side_effect=local_answer), TestClient(app) as client:
                for path in ('/api/chat', '/api/chat/tiered'):
                    for question, keys in (
                        ('我心脏疼', ['chest_pain']),
                        ('我胸闷', ['chest_pain']),
                        ('我心脏疼，没有胸闷', ['chest_pain']),
                        ('妈妈走两步就喘不上气，没有心脏疼', ['breath']),
                        ('刚才晕过去了，现在醒了，持续约10秒', ['consciousness']),
                        ('突然左边胳膊抬不起，右边没事', ['stroke']),
                        ('鼻血止不住，持续10分钟', ['bleeding']),
                        ('吃饭时喉咙卡住了说不出话', ['choking']),
                        ('突然头疼得厉害，和以前不一样', ['severe_headache']),
                        ('舌头迅速肿了，吞咽困难，没有皮疹', ['severe_allergy']),
                        ('我身体难受，快撑不住了', ['emergency_other']),
                        ('我心脏疼，喘不上气', ['chest_pain', 'breath']),
                    ):
                        with self.subTest(path=path, question=question):
                            response = client.post(path, json={'question': question})
                            self.assertEqual(response.status_code, 200, response.text)
                            result = response.json()
                            self.assertTrue(result['emergency'])
                            self.assertEqual(result['reported_question'], question)
                            self.assertEqual(result['emergency_labels'], category_labels(keys))
                            if path.endswith('tiered'):
                                for field in ('elder_view', 'family_view'):
                                    self.assertIn('120', result[field]['seek'])
                                    self.assertNotIn('胸闷', result[field]['seek'])
        finally:
            engine.dispose()

    def test_family_message_and_outbox_separate_risk_from_original_quote(self):
        from core import emergency_alert
        from db.database import Base
        from db.models import User, FamilyBinding, FamilyMessage, NotificationOutbox
        engine = create_engine('sqlite://', poolclass=StaticPool,
                               connect_args={'check_same_thread': False})
        sessions = sessionmaker(bind=engine, expire_on_commit=False)
        Base.metadata.create_all(engine)
        try:
            with sessions() as db:
                elder = User(phone='synthetic-elder', nickname='测试长辈', password_hash='test',
                             role='elder', birth_ym='1950-01', sync_summary_to_family=True)
                family = User(phone='synthetic-family', nickname='测试家属', password_hash='test', role='family')
                db.add_all([elder, family]); db.commit()
                db.add(FamilyBinding(elder_id=elder.id, family_id=family.id,
                                     status='active', invite_code='SYN001')); db.commit()
            question = '我心脏疼，' + '我正在等家人回来。' * 30 + '没有胸闷，开始约10分钟。'
            emergency_alert._last_notify.clear()
            with patch('services.notification_outbox.process_pending', return_value=None):
                worker = emergency_alert.notify_family_async(sessions, elder, question, ['chest_pain'])
                worker.join(timeout=5)
                self.assertFalse(worker.is_alive())
            with sessions() as db:
                message = db.query(FamilyMessage).one()
                self.assertEqual(message.content['question'], question[:200])
                self.assertEqual(message.content['reported_question'], question)
                self.assertEqual(message.content['emergency_labels'], '胸部不适相关危险信号')
                outbox = db.query(NotificationOutbox).one()
                self.assertIn('提醒类别', outbox.content)
                self.assertNotIn('胸闷', outbox.content)
                self.assertIn('120', outbox.content)
        finally:
            engine.dispose()


if __name__ == '__main__':
    unittest.main()

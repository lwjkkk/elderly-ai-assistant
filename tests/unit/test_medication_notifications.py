"""Real local HTTP, file SQLite and concurrency; transport is explicitly simulated."""
import sys,unittest,tempfile
from pathlib import Path
from datetime import datetime,timedelta,timezone
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from sqlalchemy import create_engine,text,inspect
from sqlalchemy.orm import sessionmaker
from fastapi import FastAPI
from fastapi.testclient import TestClient
from db.database import Base,get_db
from db.models import User,FamilyBinding,Medication,MedicationLog,NotificationOutbox,FamilyMessage
from api import meds,messages
from core.security import get_current_user
from services import scheduler,push,notification_outbox

ZONE=timezone(timedelta(hours=8))
NOW=datetime(2026,10,26,8,0,tzinfo=ZONE)
class Clock(datetime):
 current=NOW
 @classmethod
 def now(cls,tz=None):return cls.current.astimezone(tz) if tz else cls.current.replace(tzinfo=None)
class Transport(push.PushAdapter):
 name='test_transport'
 def __init__(self,result=None,error=False):self.result=result or {'status':'submitted'};self.error=error;self.calls=0
 def send(self,*args):
  self.calls+=1
  if self.error:raise RuntimeError('injected transport outage; no real phone push')
  return self.result

class Tests(unittest.TestCase):
 def setUp(self):
  Clock.current=NOW
  self.temp=tempfile.TemporaryDirectory(prefix='med_notice_',dir=Path(__file__).parent)
  self.engine=create_engine('sqlite:///'+str(Path(self.temp.name)/'local.db'),connect_args={'check_same_thread':False,'timeout':20})
  Base.metadata.create_all(self.engine);self.sessions=sessionmaker(bind=self.engine)
  with self.sessions() as db:
   db.add_all([User(id=1,role='elder',phone='test1',password_hash='x',nickname='测试',birth_ym='1950-01'),User(id=2,role='family',phone='test2',password_hash='x',nickname='家属'),User(id=3,role='family',phone='test3',password_hash='x',nickname='其他')]);db.flush()
   db.add(FamilyBinding(id=1,elder_id=1,family_id=2,status='active',invite_code='synthetic-fixture'))
   db.add(Medication(id=1,elder_id=1,created_by=1,name='合成测试药',dosage='遵医嘱',frequency='每日',times=['08:00'],start_date='2026-10-26'));db.commit()
  self.current=1
  def db_override():
   with self.sessions() as db:yield db
  def user_override():
   with self.sessions() as db:return db.get(User,self.current)
  app=FastAPI();app.include_router(meds.router);app.include_router(messages.router)
  app.dependency_overrides[get_db]=db_override;app.dependency_overrides[get_current_user]=user_override
  self.client=TestClient(app);self.clock=patch.object(meds,'datetime',Clock);self.clock.start()
  self.factory=patch.object(scheduler,'SessionLocal',self.sessions);self.factory.start()
  self.original=push._active;push.set_adapter(push.MemoryPushAdapter());push.clear_sent()
 def tearDown(self):
  self.clock.stop();self.factory.stop();push.set_adapter(self.original);self.client.close();self.engine.dispose();self.temp.cleanup()
 def checkin(self,day=None,slot='08:00'):
  data={'medication_id':1,'slot':slot}
  if day:data['date']=day
  return self.client.post('/api/meds/checkin',json=data)
 def set_med(self,**kwargs):
  with self.sessions() as db:
   m=db.get(Medication,1)
   for k,v in kwargs.items():setattr(m,k,v)
   db.commit()
 def due(self,now=NOW):return scheduler.run_reminder_cycle(now)
 def count(self,model):
  with self.sessions() as db:return db.query(model).count()
 def retry(self,now=NOW):return notification_outbox.process_pending(self.sessions,now=now)
 def failed_due(self):
  push.set_adapter(Transport(error=True));self.due();push.set_adapter(push.MemoryPushAdapter());push.clear_sent()
 def test_exact_deadline_accepts(self):
  Clock.current=NOW+timedelta(minutes=60);self.assertEqual(self.checkin().status_code,200)
 def test_one_second_past_rejects_without_log(self):
  Clock.current=NOW+timedelta(minutes=60,seconds=1);self.assertEqual(self.checkin().status_code,400);self.assertEqual(self.count(MedicationLog),0)
 def test_one_microsecond_past_rejects(self):
  Clock.current=NOW+timedelta(minutes=60,microseconds=1);self.assertEqual(self.checkin().status_code,400)
 def test_early_rejected(self):
  Clock.current=NOW-timedelta(seconds=1);self.assertEqual(self.checkin().status_code,400)
 def test_invalid_calendar_rejected(self):self.assertEqual(self.checkin('2026-02-31').status_code,400)
 def test_repeated_checkin_idempotent(self):
  a,b=self.checkin(),self.checkin();self.assertEqual(a.status_code,200);self.assertEqual(a.json()['id'],b.json()['id']);self.assertEqual(self.count(MedicationLog),1)
 def test_concurrent_checkin_idempotent(self):
  with ThreadPoolExecutor(max_workers=2) as pool:result=list(pool.map(lambda _:self.checkin(),range(2)))
  self.assertEqual([r.status_code for r in result],[200,200]);self.assertEqual(result[0].json()['id'],result[1].json()['id'])
 def test_clock_with_utc_offset_consistent(self):
  self.assertEqual(scheduler._beijing_now(NOW.astimezone(timezone.utc)),NOW.replace(tzinfo=None))
 def test_due_is_durable_and_never_delivered(self):
  rows=self.due();self.assertEqual(len(rows),2);self.assertEqual({r['status'] for r in rows},{'recorded'})
  self.assertEqual(self.count(FamilyMessage),1)
  with self.sessions() as db:
   for row in db.query(NotificationOutbox):self.assertIsNone(row.delivered_at);self.assertEqual(row.channel,'in_app')
 def test_due_repeat_no_duplicates(self):
  self.due();self.due();self.assertEqual(self.count(NotificationOutbox),2);self.assertEqual(self.count(FamilyMessage),1);self.assertEqual(len(push.get_sent()),2)
 def test_concurrent_scan_no_duplicates(self):
  with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(lambda _:self.due(),range(2)))
  self.assertEqual(self.count(NotificationOutbox),2);self.assertEqual(self.count(FamilyMessage),1);self.assertEqual(self.count(MedicationLog),1);self.assertEqual(len(push.get_sent()),2)
 def test_existing_pending_log_still_stages_missing_notice(self):
  with self.sessions() as db:db.add(MedicationLog(medication_id=1,elder_id=1,date='2026-10-26',slot='08:00',status='pending'));db.commit()
  self.assertEqual(len(self.due()),2)
 def test_taken_not_reminded(self):self.checkin();self.assertEqual(self.due(),[]);self.assertEqual(self.count(NotificationOutbox),0)
 def test_future_start_not_queued(self):self.set_med(start_date='2026-10-27');self.assertEqual(self.due(),[])
 def test_late_restart_catches_due_only_in_window(self):
  self.assertEqual(len(self.due(NOW+timedelta(minutes=10))),2)
 def test_after_deadline_not_reminded(self):self.assertEqual(self.due(NOW+timedelta(minutes=60,seconds=1)),[])
 def test_transport_failure_does_not_undo_cards_and_logs(self):
  self.failed_due();self.assertEqual(self.count(FamilyMessage),1);self.assertEqual(self.count(MedicationLog),1)
  with self.sessions() as db:self.assertEqual({r.status for r in db.query(NotificationOutbox)},{'failed'})
  self.assertEqual(self.retry()['recorded'],2)
 def test_rollback_removes_log_outbox_and_family_card(self):
  from services.medication_notifications import stage as real_stage
  def fail(*args,**kwargs):real_stage(*args,**kwargs);raise RuntimeError('injected before commit')
  with patch.object(scheduler,'stage',side_effect=fail):
   with self.assertRaises(RuntimeError):self.due()
  self.assertEqual(self.count(MedicationLog),0);self.assertEqual(self.count(NotificationOutbox),0);self.assertEqual(self.count(FamilyMessage),0)
 def test_retry_after_checkin_suppressed(self):
  self.failed_due();self.checkin();self.assertEqual(self.retry()['suppressed'],2);self.assertEqual(push.get_sent(),[])
 def test_retry_after_delete_suppressed(self):
  self.failed_due();self.client.delete('/api/meds/1');self.assertEqual(self.retry()['suppressed'],2)
 def test_retry_after_schedule_change_suppressed(self):
  self.failed_due();self.set_med(times=['10:00']);self.assertEqual(self.retry()['suppressed'],2)
 def test_expired_due_retry_suppressed(self):
  self.failed_due();self.assertEqual(self.retry(NOW+timedelta(minutes=60,seconds=1))['suppressed'],2)
 def test_unbinding_suppresses_family_only(self):
  self.failed_due()
  with self.sessions() as db:db.get(FamilyBinding,1).status='unbound';db.commit()
  result=self.retry();self.assertEqual((result['recorded'],result['suppressed']),(1,1))
 def test_younger_private_suppresses_family_at_stage(self):
  with self.sessions() as db:u=db.get(User,1);u.birth_ym='2000-01';u.sync_summary_to_family=False;db.commit()
  self.assertEqual(len(self.due()),1);self.assertEqual(self.count(FamilyMessage),0)
 def test_unknown_birth_suppresses_family_at_stage(self):
  with self.sessions() as db:db.get(User,1).birth_ym=None;db.commit()
  self.assertEqual(len(self.due()),1)
 def test_privacy_revoked_between_stage_and_retry(self):
  self.failed_due()
  with self.sessions() as db:u=db.get(User,1);u.birth_ym='2000-01';u.sync_summary_to_family=False;db.commit()
  result=self.retry();self.assertEqual((result['recorded'],result['suppressed']),(1,1))
 def test_missed_exact_deadline_no_missed(self):self.assertEqual(scheduler.run_missed_cycle(NOW+timedelta(minutes=60)),[])
 def test_missed_family_card_is_persisted_and_not_a_dose_claim(self):
  self.assertEqual(len(scheduler.run_missed_cycle(NOW+timedelta(minutes=60,seconds=1))),1)
  self.assertEqual(self.count(FamilyMessage),1)
  with self.sessions() as db:
   message=db.query(FamilyMessage).one();self.assertIn('不代表实际未服药',message.content['message']);self.assertEqual(message.kind,'health')
  self.current=2
  response=self.client.get('/api/messages/1').json()[0]
  self.assertEqual(response['kind'],'health');self.assertEqual(response['content']['type'],'medication_missed');self.assertTrue(response['content']['lines'])
 def test_legacy_medication_emergency_kind_read_as_health_without_db_rewrite(self):
  with self.sessions() as db:
   db.add(FamilyMessage(binding_id=1,sender_id=1,kind='emergency_alert',content={'type':'medication_missed','origin':'system','title':'未打卡','lines':['请联系确认，不代表实际未服药']}));db.commit()
  self.current=2
  response=self.client.get('/api/messages/1').json()[0];self.assertEqual(response['kind'],'health');self.assertEqual(response['content']['lines'],['请联系确认，不代表实际未服药'])
  with self.sessions() as db:self.assertEqual(db.query(FamilyMessage).one().kind,'emergency_alert')
 def test_genuine_symptom_emergency_kind_is_preserved(self):
  with self.sessions() as db:
   db.add(FamilyMessage(binding_id=1,sender_id=1,kind='emergency_alert',content={'type':'emergency_chat','origin':'system','emergency_labels':['紧急症状'],'advice':'立即求助'}));db.commit()
  self.current=2;response=self.client.get('/api/messages/1').json()[0];self.assertEqual(response['kind'],'emergency_alert');self.assertEqual(response['content']['advice'],'立即求助')
 def test_missed_repeat_once(self):
  scheduler.run_missed_cycle(NOW+timedelta(hours=2));scheduler.run_missed_cycle(NOW+timedelta(hours=2));self.assertEqual(self.count(FamilyMessage),1);self.assertEqual(self.count(NotificationOutbox),1)
 def test_yesterday_non_crossing_slots_not_backfilled(self):
  self.set_med(start_date='2026-10-25')
  self.assertEqual(scheduler.run_missed_cycle(NOW),[]);self.assertEqual(self.count(FamilyMessage),0)
 def test_invalid_legacy_slot_does_not_stop_valid_one(self):
  self.set_med(times=['broken','25:99','08:00']);self.assertEqual(len(self.due()),2)
 def test_whitespace_in_new_plan_is_canonicalized(self):
  response=self.client.put('/api/meds/1',json={'times':[' 08:00 ']})
  self.assertEqual(response.status_code,200);self.assertEqual(response.json()['times'],['08:00']);self.assertEqual(len(self.due()),2)
 def test_midnight_due_and_missed(self):
  self.set_med(times=['23:30'],start_date='2026-10-25')
  midnight=NOW.replace(hour=0,minute=30)
  self.assertEqual(len(self.due(midnight)),2);self.assertEqual(scheduler.run_missed_cycle(midnight),[])
  self.assertEqual(len(scheduler.run_missed_cycle(midnight+timedelta(seconds=1))),1)
  with self.sessions() as db:self.assertEqual(db.query(MedicationLog).one().date,'2026-10-25')
 def test_taken_not_marked_missed(self):self.checkin();self.assertEqual(scheduler.run_missed_cycle(NOW+timedelta(hours=2)),[])
 def test_maximum_retries_bounded(self):
  push.set_adapter(Transport(error=True));self.due()
  for _ in range(7):self.retry()
  with self.sessions() as db:self.assertEqual({r.retry_count for r in db.query(NotificationOutbox)},{5})
 def test_transport_acceptance_not_delivery(self):
  push.set_adapter(Transport());self.assertEqual({r['status'] for r in self.due()},{'submitted'})
  with self.sessions() as db:self.assertTrue(all(r.delivered_at is None for r in db.query(NotificationOutbox)))
 def test_transport_unproven_result_not_submitted(self):
  push.set_adapter(Transport(result={'foo':'bar'}));self.assertEqual({r['status'] for r in self.due()},{'failed'})
 def test_policy_does_not_claim_device_permissions_or_real_push(self):
  data=self.client.get('/api/meds/reminder-policy').json()
  self.assertEqual(data['checkin_grace_minutes'],60);self.assertFalse(data['remote_push']['ready']);self.assertEqual(data['local_reminder']['permission_status'],'unknown_to_server')
 def test_real_placeholder_even_with_credentials_not_ready(self):
  push.set_adapter(push.RealPushAdapter('synthetic-key','synthetic-secret',['synthetic-token']))
  result=self.client.get('/api/meds/reminder-policy').json()['remote_push'];self.assertFalse(result['ready']);self.assertEqual(result['state'],'not_implemented')
 def test_policy_requires_authentication(self):
  app=FastAPI();app.include_router(meds.router)
  with TestClient(app) as c:self.assertIn(c.get('/api/meds/reminder-policy').status_code,[401,403])
 def test_family_card_rechecked_after_privacy_disabled(self):
  self.due();self.current=2;self.assertEqual(len(self.client.get('/api/messages/1').json()),1)
  with self.sessions() as db:u=db.get(User,1);u.birth_ym='2000-01';u.sync_summary_to_family=False;db.commit()
  self.assertEqual(self.client.get('/api/messages/1').json(),[])
 def test_migration_old_outbox_keeps_records_and_is_repeatable(self):
  from db import database
  old=create_engine('sqlite:///'+str(Path(self.temp.name)/'old.db'))
  try:
   with old.begin() as conn:
    conn.execute(text('CREATE TABLE notification_outbox (id INTEGER PRIMARY KEY, elder_id INTEGER, receiver_id INTEGER, alert_id INTEGER, channel TEXT, status TEXT, retry_count INTEGER, claimed_at DATETIME, last_error TEXT, title TEXT, content TEXT, dedupe_key TEXT, created_at DATETIME, delivered_at DATETIME)'))
    conn.execute(text("INSERT INTO notification_outbox(id,elder_id,receiver_id,status,retry_count,title,content,dedupe_key) VALUES(1,1,2,'recorded',1,'old','old','legacy')"))
   with patch.object(database,'engine',old):database.init_db();database.init_db()
   self.assertTrue({'kind','medication_id','scheduled_for','expires_at'}.issubset({c['name'] for c in inspect(old).get_columns('notification_outbox')}))
   with old.connect() as conn:self.assertEqual(conn.execute(text('SELECT content FROM notification_outbox WHERE id=1')).scalar(),'old')
  finally:old.dispose()

if __name__=='__main__':unittest.main(verbosity=2)

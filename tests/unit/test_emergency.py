"""Rule/transport fault tests plus real HTTP/JWT/file-SQLite; no external model."""
import sys,json,time,tempfile,threading,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch,MagicMock
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from core import emergency_rules as rules,emergency_triage as triage,emergency_alert as alerts,agent,health_llm
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker,Session
from fastapi import FastAPI
from fastapi.testclient import TestClient
from db.database import Base,get_db
from db.models import User,FamilyBinding,FamilyMessage,NotificationOutbox
from core.security import create_access_token
from api import routes,messages,symptom
from services import push,notification_outbox

class Rules(unittest.TestCase):
 def test_critical_aliases(self):
  cases={'我心脏疼':'chest_pain','心脏痛':'chest_pain','心口窝疼':'chest_pain','左胸痛':'chest_pain','胸口发紧':'chest_pain','胸口像压着石头':'chest_pain',
         '上不来气':'breath','气接不上':'breath','吸不上气':'breath','突然晕倒':'consciousness','喊他没有反应':'consciousness',
         '半边身子没力':'stroke','一侧手脚发麻':'stroke','说话大舌头':'stroke','突然看不见':'stroke','突然走路往一边歪':'stroke',
         '鼻血止不住':'bleeding','吐血块':'bleeding','流血不止':'bleeding','老人被噎住说不出话':'choking',
         '突然剧烈头痛':'severe_headache','霹雳样头痛':'severe_headache','舌头迅速肿起来呼吸费劲':'severe_allergy'}
  for q,key in cases.items():
   with self.subTest(q=q):self.assertIn(key,rules.fast_types(q))
 def test_denials_for_each_category(self):
  for q in ['胸痛','心脏疼','呼吸困难','嘴歪','叫不醒','大量出血','噎住','突然剧烈头痛']:
   for prefix in ['没有','并无','不是','不伴有','否认']:
    with self.subTest(q=q,prefix=prefix):self.assertEqual(rules.fast_types(prefix+q),[])
 def test_education_history_hypothetical_not_current(self):
  for q in ['怎样预防中风','什么是胸痛','以前心脏疼','去年突然晕倒','假如胸口疼怎么办','如果呼吸困难该怎么办','新闻里有人吐血','正则心脏疼怎么写']:
   self.assertEqual(rules.fast_types(q),[],q)
 def test_negation_does_not_hide_other_current_symptoms(self):
  self.assertIn('breath',rules.fast_types('没有胸痛，但是喘不过气'))
  self.assertIn('chest_pain',rules.fast_types('不是呼吸困难，而是心脏疼'))
  self.assertIn('stroke',rules.fast_types('刚才一侧手脚无力，现在恢复了'))
 def test_no_blanket_dizziness_or_standing_or_minor_bleeding_emergency(self):
  for q in ['我站住了','有点发晕','晕乎乎','普通头晕','走路有点不稳','刷牙时牙龈少量出血','指尖擦破一点血','皮肤有点痒','我很心疼电影里的人']:
   self.assertEqual(rules.fast_types(q),[],q)
 def test_broad_severity_net(self):self.assertIn('emergency_other',rules.fast_types('我整个人特别难受，快撑不住了'))
 def test_novel_body_function_descriptions_reach_semantic_screen(self):
  for q in ['我心口像被人紧紧攥住，冷汗往下滴','我嘴能动，可是突然话都说不顺了，右胳膊像不是自己的','突然眼前一黑','喉咙像堵住了']:
   self.assertTrue(rules.semantic_candidate(q),q)
 def test_routine_tasks_need_no_semantic_request(self):
  for q in ['微信怎么发语音','高血压买药怎么报销','高血压饮食注意什么','怎么预防中风','没有胸痛，只是问饮食']:
   self.assertFalse(rules.semantic_candidate(q),q)

class Fallback(unittest.TestCase):
 def test_fast_positive_never_waits_for_model(self):
  with patch.object(triage,'semantic_judge',side_effect=AssertionError('must not call')):
   self.assertEqual(triage.assess('我心脏疼')['status'],'urgent')
 def test_model_positive_unknown_category_supported(self):
  with patch.object(triage,'semantic_judge',return_value=('urgent',['emergency_other'])):
   result=triage.assess('我身体像不是自己的一样')
  self.assertEqual(result['status'],'urgent');self.assertIn('120',triage.policy(result)['answer'])
 def test_failure_is_uncertain_not_normal(self):
  with patch.object(triage,'semantic_judge',side_effect=RuntimeError('synthetic failure')):
   result=triage.assess('我身体不舒服')
  self.assertEqual(result['status'],'uncertain');self.assertTrue(result['needs_review']);self.assertIn('不代表没有危险',triage.policy(result)['answer'])
 def test_negative_is_not_a_health_clearance(self):
  with patch.object(triage,'semantic_judge',return_value=('non_urgent',[])):
   result=triage.assess('我有点头晕')
  self.assertEqual(result['status'],'non_urgent');self.assertIsNone(triage.policy(result))
 def test_wall_time_timeout_and_late_result_discarded(self):
  release=threading.Event()
  def slow(q):release.wait(2);return ('urgent',['stroke'])
  try:
   with patch.object(triage,'semantic_judge',side_effect=slow),patch.object(triage,'TIMEOUT_SECONDS',.04):
    started=time.perf_counter();result=triage.assess('我身体不舒服');self.assertLess(time.perf_counter()-started,.5);self.assertEqual(result['status'],'uncertain')
  finally:release.set();time.sleep(.03)
 def test_json_schema_strict(self):
  good={'status':'urgent','types':['stroke']}
  invalid=[{'emergency':'true','types':['stroke']},{'status':'urgent','types':[]},{'status':'urgent','types':['madeup']},
           {'status':'non_urgent','types':['stroke']},{'status':True,'types':[]},[]]
  for data in [good]+invalid:
   client=MagicMock();client.with_options.return_value=client
   client.chat.completions.create.return_value=SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=json.dumps(data)))])
   with patch('core.qwen_llm._get_client',return_value=client),patch('core.qwen_llm._validate_api_key'):
    if data is good:self.assertEqual(triage.semantic_judge('人工测试'),('urgent',['stroke']))
    else:
     with self.assertRaises((ValueError,TypeError)):triage.semantic_judge('人工测试')
   self.assertEqual(client.with_options.call_args.kwargs,{'timeout':5.0,'max_retries':0})
 def test_invalid_json_fails_to_uncertain(self):
  with patch.object(triage,'semantic_judge',side_effect=ValueError('bad JSON')):self.assertEqual(triage.assess('我身体不舒服')['status'],'uncertain')
 def test_emergency_medication_boundary_is_preserved(self):
  self.assertIn('不要根据聊天决定药物片数',triage.policy(triage.assess('心脏疼，阿司匹林吃几片'))['answer'])
 def test_saturated_classifier_does_not_queue_unbounded_requests(self):
  acquired=triage._SLOTS.acquire(False)
  second=triage._SLOTS.acquire(False)
  try:
   self.assertTrue(acquired and second)
   started=time.perf_counter();result=triage.assess('我身体不舒服');self.assertLess(time.perf_counter()-started,.2);self.assertEqual(result['status'],'uncertain')
  finally:
   if acquired:triage._SLOTS.release()
   if second:triage._SLOTS.release()

class HTTP(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='emergency_',dir=Path(__file__).parent)
  self.engine=create_engine('sqlite:///'+str(Path(self.temp.name)/'test.db'),connect_args={'check_same_thread':False,'timeout':15})
  Base.metadata.create_all(self.engine);self.sessions=sessionmaker(bind=self.engine)
  with self.sessions() as db:
   db.add_all([User(id=1,role='elder',phone='synthetic-1',password_hash='x',nickname='测试',birth_ym='1950-01'),User(id=2,role='family',phone='synthetic-2',password_hash='x',nickname='家属'),User(id=3,role='family',phone='synthetic-3',password_hash='x',nickname='其他')]);db.flush()
   db.add(FamilyBinding(id=1,elder_id=1,family_id=2,status='active',invite_code='synthetic'));db.commit()
   self.tokens={i:create_access_token(db.get(User,i)) for i in (1,2,3)}
  app=FastAPI();app.include_router(routes.router);app.include_router(messages.router);app.include_router(symptom.router)
  def database():
   with self.sessions() as db:yield db
  app.dependency_overrides[get_db]=database;self.client=TestClient(app);self.workers=[]
  self.original_adapter=push._active;push.set_adapter(push.MemoryPushAdapter());push.clear_sent()
  self.summary=patch.object(routes,'save_summary_sync');self.summary.start()
  self.semantic=patch.object(triage,'semantic_judge',return_value=('non_urgent',[]));self.semantic.start()
  actual_notify=alerts.notify_family_async
  def tracked(*args,**kwargs):
   worker=actual_notify(*args,**kwargs);self.workers.append(worker);return worker
  self.notify=patch.object(alerts,'notify_family_async',side_effect=tracked);self.notify.start()
 def tearDown(self):
  for worker in self.workers:worker.join(5)
  self.notify.stop();self.summary.stop();self.semantic.stop();self.client.close();push.set_adapter(self.original_adapter);self.engine.dispose();self.temp.cleanup()
 def headers(self,user=1):return {'Authorization':'Bearer '+self.tokens[user]}
 def ask(self,q,path='/api/chat/tiered',logged=True):
  response=self.client.post(path,json={'question':q},headers=self.headers() if logged else {})
  self.assertEqual(response.status_code,200,response.text);self.join();return response.json()
 def join(self):
  for worker in self.workers:worker.join(5);self.assertFalse(worker.is_alive())
 def count(self,model):
  with self.sessions() as db:return db.query(model).count()
 def change(self,**kwargs):
  with self.sessions() as db:
   user=db.get(User,1)
   for k,v in kwargs.items():setattr(user,k,v)
   db.commit()
 def test_heart_pain_both_routes_preempts_generation_and_persists_one_alert(self):
  with patch.object(agent,'call_qwen',side_effect=AssertionError('no main generation')),patch.object(agent,'_retrieve_references',side_effect=AssertionError('no retrieval')):
   for path in ['/api/chat','/api/chat/tiered']:
    answer=self.ask('我心脏疼',path);self.assertTrue(answer['emergency']);self.assertIn('120',answer['answer'])
  self.assertEqual(self.count(FamilyMessage),1);self.assertEqual(self.count(NotificationOutbox),1)
 def test_legacy_empty_emergency_array_does_not_bypass_triage(self):
  with patch.object(routes,'get_agent_answer',return_value={'answer':'普通回答','module':'daily_life','emergency_types':[]}):
   answer=self.ask('我心脏疼')
  self.assertTrue(answer['emergency']);self.assertEqual(answer['module'],'health');self.assertIn('120',answer['elder_view']['seek'])
 def test_semantic_positive_used_once_and_same_dual_view_safety(self):
  with patch.object(triage,'semantic_judge',return_value=('urgent',['stroke'])) as judge:
   answer=self.ask('我嘴能动，但是话说不顺了，右胳膊像不是自己的')
  judge.assert_called_once();self.assertTrue(answer['emergency']);self.assertEqual(answer['elder_view']['seek'],answer['family_view']['seek'])
 def test_semantic_failure_gives_uncertainty_without_main_generation(self):
  with patch.object(triage,'semantic_judge',side_effect=RuntimeError('injected outage')),patch.object(agent,'call_qwen',side_effect=AssertionError('no retry generation')):
   answer=self.ask('我身体不舒服')
  self.assertFalse(answer['emergency']);self.assertTrue(answer['urgent_review_required']);self.assertIn('无法可靠核定',answer['answer']);self.assertEqual(self.count(FamilyMessage),0)
 def test_missing_birth_keeps_own_emergency_and_blocks_family(self):
  self.change(birth_ym=None);answer=self.ask('心脏疼');self.assertTrue(answer['emergency']);self.assertEqual(answer['family_notification_status'],'profile_incomplete');self.assertEqual(self.count(FamilyMessage),0)
 def test_younger_privacy_blocks_family(self):
  self.change(birth_ym='2000-01',sync_summary_to_family=False);answer=self.ask('心脏疼');self.assertTrue(answer['emergency']);self.assertEqual(answer['family_notification_status'],'sharing_disabled');self.assertEqual(self.count(FamilyMessage),0)
 def test_senior_forced_share_preserved(self):
  self.change(sync_summary_to_family=False);answer=self.ask('心脏疼');self.assertTrue(answer['emergency']);self.assertEqual(self.count(FamilyMessage),1)
 def test_anonymous_still_gets_emergency_no_family_write(self):
  answer=self.ask('心脏疼',logged=False);self.assertTrue(answer['emergency']);self.assertEqual(self.count(FamilyMessage),0)
 def test_unbound_user_cannot_read_alert(self):
  self.ask('心脏疼');self.assertEqual(self.client.get('/api/messages/1',headers=self.headers(3)).status_code,403)
 def test_different_categories_not_suppressed_by_previous_chest_alert(self):
  self.ask('心脏疼');self.ask('喘不上气');self.assertEqual(self.count(FamilyMessage),2);self.assertEqual(self.count(NotificationOutbox),2)
 def test_dedupe_survives_memory_cache_clear(self):
  self.ask('心脏疼');alerts._last_notify.clear();self.ask('心脏疼');self.assertEqual(self.count(FamilyMessage),1)
 def test_duplicate_bindings_do_not_duplicate_or_rollback_alert(self):
  with self.sessions() as db:db.add(FamilyBinding(elder_id=1,family_id=2,status='active',invite_code='duplicate'));db.commit()
  self.ask('心脏疼');self.assertEqual(self.count(FamilyMessage),1)
 def test_concurrent_workers_dedupe(self):
  a=alerts.notify_family_async(self.sessions,SimpleNamespace(id=1),'心脏疼',['chest_pain']);b=alerts.notify_family_async(self.sessions,SimpleNamespace(id=1),'心脏疼',['chest_pain']);a.join(5);b.join(5)
  self.assertEqual(self.count(FamilyMessage),1);self.assertEqual(self.count(NotificationOutbox),1)
 def test_rollback_does_not_poison_retry_dedupe(self):
  class Broken(Session):
   def commit(self):raise RuntimeError('injected commit failure')
  bad=sessionmaker(bind=self.engine,class_=Broken)
  worker=alerts.notify_family_async(bad,SimpleNamespace(id=1),'心脏疼',['chest_pain']);worker.join(5)
  self.assertEqual(self.count(FamilyMessage),0);self.ask('心脏疼');self.assertEqual(self.count(FamilyMessage),1)
 def test_dispatch_failure_preserves_message(self):
  with patch.object(push,'send_push',side_effect=RuntimeError('injected push failure')):self.ask('心脏疼')
  self.assertEqual(self.count(FamilyMessage),1)
  with self.sessions() as db:self.assertEqual(db.query(NotificationOutbox).one().status,'failed')
 def test_revoke_before_retry_suppresses_and_hides_existing_health_content(self):
  with patch.object(notification_outbox,'process_pending',return_value={}):self.ask('心脏疼')
  self.change(birth_ym='2000-01',sync_summary_to_family=False)
  result=notification_outbox.process_pending(self.sessions);self.assertEqual(result['suppressed'],1)
  self.assertEqual(self.client.get('/api/messages/1',headers=self.headers(2)).json(),[])
 def test_symptom_endpoint_shares_rules_and_authorized_family_event(self):
  result=self.client.post('/api/symptom-check',json={'input_text':'心脏疼'},headers=self.headers());self.assertEqual(result.status_code,200,result.text);self.join();self.assertEqual(result.json()['risk'],'red');self.assertEqual(self.count(FamilyMessage),1)
 def test_symptom_unknown_birth_does_not_leak(self):
  self.change(birth_ym=None)
  result=self.client.post('/api/symptom-check',json={'input_text':'心脏疼'},headers=self.headers());self.assertEqual(result.status_code,200,result.text);self.join();self.assertEqual(result.json()['risk'],'red');self.assertEqual(self.count(FamilyMessage),0)
 def test_generation_red_risk_upgrades_same_symptom_assessment(self):
  with patch.object(health_llm,'_retrieve_references',create=True,return_value=([],'none')):
   with patch.object(agent,'_retrieve_references',return_value=([],'none')),patch.object(health_llm,'call_qwen',return_value='请立即求助。\nRISK: red'):
    answer=health_llm.symptom_assessment('今天咳嗽')
  self.assertEqual(answer['risk'],'red');self.assertEqual(answer['emergency_types'],['emergency_other'])

if __name__=='__main__':unittest.main(verbosity=2)

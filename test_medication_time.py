import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from db.database import Base, get_db
from db.models import User, Medication, MedicationLog
from core.security import get_current_user
from api import meds
from services import scheduler

class FixedClock(datetime):
    @classmethod
    def now(cls, tz=None):
        return cls(2026, 10, 13, 8, 0, tzinfo=tz)

class MedicationTimeTests(unittest.TestCase):
    def setUp(self):
        self.engine=create_engine('sqlite://',connect_args={'check_same_thread':False},poolclass=StaticPool)
        Base.metadata.create_all(self.engine)
        self.Session=sessionmaker(bind=self.engine)
        self.db=self.Session()
        self.user=User(phone='13900000001',password_hash='test',nickname='测试',role='elder')
        self.db.add(self.user);self.db.commit();self.db.refresh(self.user)
        self.med=Medication(elder_id=self.user.id,created_by=self.user.id,name='测试药',dosage='遵医嘱',frequency='每日',times=['08:00','09:00'],start_date='2026-10-13')
        self.db.add(self.med);self.db.commit();self.db.refresh(self.med)
        app=FastAPI();app.include_router(meds.router)
        def session():
            db=self.Session()
            try: yield db
            finally: db.close()
        app.dependency_overrides[get_db]=session
        app.dependency_overrides[get_current_user]=lambda:self.user
        self.client=TestClient(app)
        self.clock=patch.object(meds,'datetime',FixedClock);self.clock.start()
    def tearDown(self):
        self.clock.stop();self.client.close();self.db.close();self.engine.dispose()
    def check(self,slot,date=None):
        body={'medication_id':self.med.id,'slot':slot}
        if date:body['date']=date
        return self.client.post('/api/meds/checkin',json=body)
    def test_future_time_rejected_without_record(self):
        self.assertEqual(self.check('09:00').status_code,400)
        self.assertEqual(self.db.query(MedicationLog).count(),0)
    def test_exact_time_accepted_and_idempotent(self):
        a=self.check('08:00');b=self.check('08:00')
        self.assertEqual(a.status_code,200);self.assertEqual(b.json()['id'],a.json()['id'])
        self.assertEqual(self.db.query(MedicationLog).count(),1)
    def test_future_day_rejected(self):
        self.assertEqual(self.check('08:00','2026-10-14').status_code,400)
    def test_unknown_slot_rejected(self):
        self.assertEqual(self.check('07:00').status_code,400)
    def test_before_start_date_rejected(self):
        self.assertEqual(self.check('08:00','2026-10-12').status_code,400)
    def test_scheduler_uses_beijing_date(self):
        local=scheduler._beijing_now(datetime(2026,10,12,16,0,tzinfo=timezone.utc))
        self.assertEqual(local,datetime(2026,10,13,0,0))
    def test_future_start_date_not_reminded_or_missed(self):
        self.med.start_date='2026-10-14';self.db.commit()
        with patch.object(scheduler,'SessionLocal',self.Session):
            self.assertEqual(scheduler.run_reminder_cycle(datetime(2026,10,13,8,0)),[])
            self.assertEqual(scheduler.run_missed_cycle(datetime(2026,10,13,12,0)),[])
        self.assertEqual(self.db.query(MedicationLog).count(),0)
    def test_future_start_date_hidden_from_today(self):
        self.med.start_date='2026-10-14';self.db.commit()
        self.assertEqual(self.client.get('/api/meds/today').json(),[])

if __name__=='__main__': unittest.main()

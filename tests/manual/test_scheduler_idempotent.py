# -*- coding: utf-8 -*-
"""验证用药定时任务幂等性、漏服判定、start_date 边界。"""

# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"
os.environ["RUN_SCHEDULER"] = "0"  # 不启动 APScheduler

from datetime import datetime
from db.database import SessionLocal, engine, Base
from db.models import Medication, MedicationLog
from services.scheduler import run_reminder_cycle, run_missed_cycle

Base.metadata.drop_all(bind=engine)
Base.metadata.create_all(bind=engine)
db = SessionLocal()

# 造一条药：今天 08:00 / 20:00 两次
med = Medication(elder_id=1, created_by=1, name="阿司匹林", dosage="1片",
                 frequency="每日两次", times=["08:00", "20:00"], start_date="2026-10-01")
db.add(med); db.commit()

# 1. 到点创建待服记录
t = datetime(2026, 10, 20, 8, 0)
run_reminder_cycle(now=t)
n = db.query(MedicationLog).filter_by(medication_id=med.id, date="2026-10-20", slot="08:00").count()
assert n == 1, f"应创建1条pending，实际{n}"
log = db.query(MedicationLog).filter_by(medication_id=med.id, date="2026-10-20", slot="08:00").first()
assert log.status == "pending"
print("[1] 到点创建 pending OK")

# 2. 同一分钟再扫一次不重复
run_reminder_cycle(now=t)
n = db.query(MedicationLog).filter_by(medication_id=med.id, date="2026-10-20", slot="08:00").count()
assert n == 1, f"重复扫描仍应只有1条，实际{n}"
print("[2] 重复扫描不重复创建 OK")

# 3. start_date 之前不提醒
med2 = Medication(elder_id=1, created_by=1, name="降压药", dosage="1粒",
                  frequency="每日一次", times=["09:00"], start_date="2026-10-25")
db.add(med2); db.commit()
run_reminder_cycle(now=datetime(2026, 10, 20, 9, 0))
n2 = db.query(MedicationLog).filter_by(medication_id=med2.id).count()
assert n2 == 0, f"start_date 之前不应创建记录，实际{n2}"
print("[3] start_date 之前不提醒 OK")

# 4. 漏服标记：08:00 过了 31 分钟仍 pending -> missed
run_missed_cycle(now=datetime(2026, 10, 20, 8, 31))
log = db.query(MedicationLog).filter_by(medication_id=med.id, date="2026-10-20", slot="08:00").first()
assert log.status == "missed", f"31分钟后应missed，实际{log.status}"
print("[4] 宽限期后标记 missed OK")

# 5. 宽限期内不标记
run_missed_cycle(now=datetime(2026, 10, 20, 8, 15))
log = db.query(MedicationLog).filter_by(medication_id=med.id, date="2026-10-20", slot="08:00").first()
assert log.status == "missed", "已missed不回退"
print("[5] 已missed不回退 OK")

# 6. 多时间点只处理到点的
run_reminder_cycle(now=datetime(2026, 10, 20, 20, 0))
n8 = db.query(MedicationLog).filter_by(medication_id=med.id, slot="08:00").count()
n20 = db.query(MedicationLog).filter_by(medication_id=med.id, slot="20:00").count()
assert n8 == 1 and n20 == 1, f"08:00和20:00各1条，实际08={n8} 20={n20}"
print("[6] 不同时间点分别记录 OK")

print("\n[ALL PASS] 定时任务幂等/边界/漏服验证通过")
db.close()

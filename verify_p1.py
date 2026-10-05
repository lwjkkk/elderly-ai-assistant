# P1 验证：meds.start_date、vitals.measured_at、体征拍照识别（mock LLM）
import random

from fastapi.testclient import TestClient

from db.database import init_db, get_db
from db.models import User, Medication, Vitals
import api.vitals
import api.meds
from main import app

init_db()
client = TestClient(app)


def main():
    phone = f"13{random.randint(0, 999999999):09d}"
    assert client.post("/api/auth/register", json={"phone": phone, "password": "123456", "nickname": "测试老人", "role": "elder"}).status_code == 201
    tok = client.post("/api/auth/login", json={"phone": phone, "password": "123456"}).json()["access_token"]
    h = {"Authorization": f"Bearer {tok}"}

    # P1-1: meds start_date
    r = client.post("/api/meds", json={"name": "阿司匹林", "dosage": "1片", "frequency": "每日一次", "times": ["08:00"], "start_date": "2026-10-01"}, headers=h)
    print("[meds+start_date]", r.status_code)
    assert r.status_code == 200 and r.json()["start_date"] == "2026-10-01"
    med_id = r.json()["id"]
    # update 也能改
    r = client.put(f"/api/meds/{med_id}", json={"start_date": "2026-10-02"}, headers=h)
    assert r.json()["start_date"] == "2026-10-02"
    print("[meds update start_date] OK")

    # P1-2: vitals measured_at（补录历史日期）
    r = client.post("/api/vitals", json={"type": "bp", "systolic": 138, "diastolic": 88, "measured_at": "2026-09-20 08:30"}, headers=h)
    print("[vitals+measured_at]", r.status_code)
    assert r.status_code == 200
    rec = r.json()
    assert rec["measured_at"].startswith("2026-09-20"), rec["measured_at"]
    # 不传默认当天
    r2 = client.post("/api/vitals", json={"type": "bs", "value": 6.1}, headers=h)
    assert r2.status_code == 200 and r2.json()["measured_at"]
    print("[vitals 默认当天] OK")

    # P1-3: 体征拍照识别（mock OCR + LLM）
    api.vitals.recognize_image = lambda b64: "血压 138/88 mmHg"
    api.vitals.call_qwen = lambda sp, up: "TYPE: bp\nSYSTOLIC: 138\nDIASTOLIC: 88\nUNIT: mmHg"
    r = client.post("/api/vitals/recognize", json={"image_base64": "ZmFrZQ=="}, headers=h)
    print("[体征识别]", r.status_code, r.json())
    assert r.status_code == 200
    b = r.json()
    assert b["type"] == "bp" and b["systolic"] == 138 and b["diastolic"] == 88
    assert b["raw_text"]

    # mock 血糖识别
    api.vitals.call_qwen = lambda sp, up: "TYPE: bs\nVALUE: 6.1\nUNIT: mmol/L"
    r = client.post("/api/vitals/recognize", json={"image_base64": "ZmFrZQ=="}, headers=h)
    assert r.status_code == 200 and r.json()["type"] == "bs" and r.json()["value"] == 6.1
    print("[血糖识别]", r.status_code, r.json())

    # 识别结果可接着落库
    r = client.post("/api/vitals", json={"type": b["type"], "systolic": b["systolic"], "diastolic": b["diastolic"]}, headers=h)
    assert r.status_code == 200
    print("[识别结果落库] OK")

    # 清理
    db = next(get_db())
    db.query(Vitals).filter(Vitals.elder_id == db.query(User).filter(User.phone == phone).first().id).delete()
    db.query(Medication).filter(Medication.id == med_id).delete()
    u = db.query(User).filter(User.phone == phone).first()
    if u:
        db.delete(u)
    db.commit(); db.close()

    print("\n✅ P1全部通过：meds start_date、vitals measured_at、体征拍照识别（血压/血糖）")


if __name__ == "__main__":
    main()

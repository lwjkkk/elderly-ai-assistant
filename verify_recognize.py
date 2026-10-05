# 体征拍照识别接口验证：四种类型、单位换算、字段、失败场景
import random

from fastapi.testclient import TestClient

from db.database import init_db, get_db
from db.models import User
import api.vitals
from main import app

init_db()
client = TestClient(app)


def main():
    ep = f"13{random.randint(0, 999999999):09d}"
    assert client.post("/api/auth/register", json={"phone": ep, "password": "123456", "nickname": "老人", "role": "elder"}).status_code == 201
    tok = client.post("/api/auth/login", json={"phone": ep, "password": "123456"}).json()["access_token"]
    h = {"Authorization": f"Bearer {tok}"}
    db = next(get_db()); eid = db.query(User).filter(User.phone == ep).first().id; db.close()

    # mock OCR 和 LLM
    api.vitals.recognize_image = lambda b64: "血压 135/85 mmHg"
    api.vitals.call_qwen = lambda sp, up: "TYPE: bp\nSYSTOLIC: 135\nDIASTOLIC: 85\nCONFIDENCE: 0.92"
    r = client.post("/api/vitals/recognize", json={"image_base64": "ZmFrZQ==", "elder_id": eid}, headers=h)
    print("[bp]", r.status_code, r.json())
    assert r.status_code == 200
    b = r.json()
    assert b["type"] == "bp" and b["systolic"] == 135 and b["diastolic"] == 85
    assert b["unit"] == "mmHg" and b["confidence"] == 0.92 and b["ocr_text"]

    # 血糖 mg/dL -> mmol/L 换算
    api.vitals.call_qwen = lambda sp, up: "TYPE: bs\nVALUE: 108\nUNIT: mg/dL\nCONFIDENCE: 0.9"
    r = client.post("/api/vitals/recognize", json={"image_base64": "ZmFrZQ=="}, headers=h)
    assert r.status_code == 200 and r.json()["type"] == "bs"
    assert abs(r.json()["value"] - 6.0) < 0.01 and r.json()["unit"] == "mmol/L", r.json()
    print("[bs mg/dL→mmol/L]", r.status_code, r.json()["value"], r.json()["unit"])

    # 血糖 mmol/L 原样
    api.vitals.call_qwen = lambda sp, up: "TYPE: bs\nVALUE: 6.1\nUNIT: mmol/L"
    r = client.post("/api/vitals/recognize", json={"image_base64": "ZmFrZQ=="}, headers=h)
    assert r.json()["value"] == 6.1 and r.json()["unit"] == "mmol/L"
    print("[bs mmol/L]", r.json()["value"], r.json()["unit"])

    # 心率
    api.vitals.call_qwen = lambda sp, up: "TYPE: hr\nVALUE: 72\nUNIT: bpm"
    r = client.post("/api/vitals/recognize", json={"image_base64": "ZmFrZQ=="}, headers=h)
    assert r.status_code == 200 and r.json()["value"] == 72.0 and r.json()["unit"] == "次/分"
    print("[hr]", r.json()["value"], r.json()["unit"])

    # 体重一位小数
    api.vitals.call_qwen = lambda sp, up: "TYPE: weight\nVALUE: 62.37\nUNIT: kg"
    r = client.post("/api/vitals/recognize", json={"image_base64": "ZmFrZQ=="}, headers=h)
    assert r.json()["value"] == 62.4 and r.json()["unit"] == "kg", r.json()
    print("[weight 一位小数]", r.json()["value"], r.json()["unit"])

    # 失败场景：LLM 输出 NONE
    api.vitals.call_qwen = lambda sp, up: "NONE"
    r = client.post("/api/vitals/recognize", json={"image_base64": "ZmFrZQ=="}, headers=h)
    assert r.status_code == 400 and "未识别到体征数值" in r.json()["detail"]
    print("[NONE→400]", r.status_code, r.json()["detail"])

    # 失败场景：OCR 空
    api.vitals.recognize_image = lambda b64: ""
    r = client.post("/api/vitals/recognize", json={"image_base64": "ZmFrZQ=="}, headers=h)
    assert r.status_code == 400 and "未识别到数字" in r.json()["detail"]
    print("[OCR空→400]", r.status_code, r.json()["detail"])

    # 清理
    db = next(get_db())
    u = db.query(User).filter(User.phone == ep).first()
    if u: db.delete(u)
    db.commit(); db.close()

    print("\n✅ 体征识别全部通过：四种类型、单位换算、confidence、ocr_text、失败400")


if __name__ == "__main__":
    main()


# Repository imports remain valid after script classification.
import os as _os
if _os.environ.get('SILVER_MANUAL_SANDBOX') != '1':
    raise SystemExit('Use python scripts/run_manual.py to isolate this script')
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0,str(_Path(__file__).resolve().parents[2]))
import io,json,tempfile
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from fastapi import FastAPI
from fastapi.testclient import TestClient
from db.database import Base,get_db
from db.models import User,HealthReport,ConsultRecord
from core.security import create_access_token
from api import reports,consults
engine=create_engine('sqlite://',connect_args={'check_same_thread':False},poolclass=StaticPool)
Base.metadata.create_all(engine);Session=sessionmaker(bind=engine)
db=Session()
owner=User(phone='13900000001',nickname='测试所有者',password_hash='test',role='elder')
other=User(phone='13900000002',nickname='测试其他老人',password_hash='test',role='elder')
db.add_all([owner,other]);db.commit();db.refresh(owner);db.refresh(other)
db.add(HealthReport(elder_id=owner.id,image_url='/api/reports/image/test.png',ocr_text='',advice_text=''))
db.add(ConsultRecord(elder_id=owner.id,audio_url='/api/consults/audio/test.wav'))
db.commit()
def session():
    conn=Session()
    try:yield conn
    finally:conn.close()
app=FastAPI();app.include_router(reports.router);app.include_router(consults.router)
app.dependency_overrides[get_db]=session;client=TestClient(app)
result={}
with tempfile.TemporaryDirectory(prefix='file_contract_') as folder:
    Image.new('RGB',(1,1),'white').save(Path(folder)/'test.png')
    (Path(folder)/'test.wav').write_bytes(b'RIFFtestWAVE')
    with patch.object(reports,'UPLOAD_DIR',folder),patch.object(consults,'UPLOAD_DIR',folder):
        for label,user in [('owner',owner),('unrelated_elder',other)]:
            headers={'Authorization':'Bearer '+create_access_token(user)}
            result[label]={path:client.get(path,headers=headers).status_code for path in ['/api/reports/image/test.png','/api/consults/audio/test.wav']}
        result['anonymous']={path:client.get(path).status_code for path in ['/api/reports/image/test.png','/api/consults/audio/test.wav']}
Path('backend_validation/file_auth_audit_20261014.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result))

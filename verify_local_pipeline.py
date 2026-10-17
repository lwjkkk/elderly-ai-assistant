import torch
import base64, io, json, time, traceback, os
from pathlib import Path
from datetime import datetime
from PIL import Image, ImageDraw, ImageFont
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from fastapi import FastAPI
from fastapi.testclient import TestClient
from db.database import Base, get_db
from db.models import User, FamilyBinding
from core.security import get_current_user
from api import vitals, drugs, reports, meds

args=__import__('sys').argv
model_only='--model-only' in args
output = Path('docs/local_model_audit.json' if model_only else 'docs/local_pdf_audit.json' if '--pdf-only' in args else 'docs/local_pipeline_audit.json')
if model_only:
    import core.qwen_llm as model
    model.QWEN_MAX_TOKENS=384
    model.QWEN_MAX_RETRIES=1
results = []
def record(stage, **data):
    results.append({'stage': stage, **data})
    output.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    print(stage, json.dumps(data, ensure_ascii=False), flush=True)
engine=create_engine('sqlite://',connect_args={'check_same_thread':False},poolclass=StaticPool)
Base.metadata.create_all(engine)
Session=sessionmaker(bind=engine)
db=Session()
elder=User(phone='13900000001',password_hash='test',nickname='OCR测试长辈',role='elder')
family=User(phone='13900000002',password_hash='test',nickname='OCR测试家属',role='family')
db.add_all([elder,family]);db.commit(); db.refresh(elder); db.refresh(family)
db.add(FamilyBinding(elder_id=elder.id,family_id=family.id,status='active',invite_code='audit1'));db.commit()
current=[elder]
def test_db():
    s=Session()
    try: yield s
    finally: s.close()
import tempfile, atexit
report_temp=tempfile.TemporaryDirectory(prefix='yunqi_report_audit_')
atexit.register(report_temp.cleanup)
reports.UPLOAD_DIR=report_temp.name
app=FastAPI()
for router in (vitals.router,drugs.router,reports.router,meds.router): app.include_router(router)
app.dependency_overrides[get_db]=test_db
app.dependency_overrides[get_current_user]=lambda:current[0]
client=TestClient(app,raise_server_exceptions=False)
font=ImageFont.truetype('C:/Windows/Fonts/simhei.ttf',42)
def sample(lines):
    image=Image.new('RGB',(1200,180+90*len(lines)),'white')
    draw=ImageDraw.Draw(image)
    for i,line in enumerate(lines): draw.text((50,50+i*90),line,font=font,fill='black')
    buff=io.BytesIO();image.save(buff,format='PNG');return buff.getvalue()
cases=[('vitals','/api/vitals/recognize',['电子血压计','收缩压 135 mmHg','舒张压 85 mmHg','心率 72 bpm']),
       ('drug','/api/drugs/query',['阿司匹林肠溶片','规格：100 mg','请遵医嘱，详见说明书']),
       ('report','/api/reports/upload',['体检报告','空腹血糖 GLU 5.1 mmol/L 参考范围 3.9-6.1','总胆固醇 TC 6.2 mmol/L 参考范围 2.8-5.2'])]
for name,path,lines in ([] if '--pdf-only' in __import__('sys').argv else cases):
    started=time.monotonic()
    print('START',name,flush=True)
    try:
        image=sample(lines)
        from core.ocr import recognize_image
        if model_only:
            ocr='\n'.join(lines)
            getattr({'vitals':vitals,'drug':drugs,'report':reports}[name], 'recognize_image')
            {'vitals':vitals,'drug':drugs,'report':reports}[name].recognize_image=lambda encoded, text=ocr:text
        else:
            ocr=recognize_image(base64.b64encode(image).decode())
        record(name+'_ocr',text=ocr,source='provided_test_text' if model_only else 'real_ocr',seconds=round(time.monotonic()-started,1))
        if name=='report': response=client.post(path,files={'file':('audit.png',image,'image/png')})
        else: response=client.post(path,json={'image_base64':base64.b64encode(image).decode()})
        try: body=response.json()
        except Exception: body={'error':response.text[:250]}
        record(name,status=response.status_code,seconds=round(time.monotonic()-started,1),body=body)
        if name=='vitals' and response.status_code==200:
            parsed=body
            r=client.post('/api/vitals',json={'type':parsed['type'],'systolic':parsed.get('systolic'),'diastolic':parsed.get('diastolic'),'value':parsed.get('value')})
            record('vitals_save',status=r.status_code)
        if name=='report' and response.status_code==200:
            file=Path(reports.UPLOAD_DIR)/body['image_url'].split('/')[-1]
            if file.exists(): file.unlink()
    except Exception as e: record(name,error=str(e),traceback=traceback.format_exc()[-900:])
# PDF does not need OCR/LLM, create an isolated test measurement even if OCR failed.
client.post('/api/vitals',json={'type':'bp','systolic':135,'diastolic':85})
client=TestClient(app,raise_server_exceptions=True)
try:
    r=client.get('/api/vitals/export',params={'days':90})
except Exception as e:
    record('pdf_trace',error=str(e),traceback=traceback.format_exc())
    client=TestClient(app,raise_server_exceptions=False)
    r=client.get('/api/vitals/export',params={'days':90})
record('elder_pdf',status=r.status_code,content_type=r.headers.get('content-type'),bytes=len(r.content),pdf_magic=r.content.startswith(b'%PDF'),error=None if r.status_code==200 else r.text[:300])
current[0]=family
r=client.get('/api/vitals/export',params={'elder_id':elder.id,'days':90})
record('family_bound_pdf',status=r.status_code,pdf_magic=r.content.startswith(b'%PDF'))
r=client.get('/api/vitals/export',params={'days':90})
record('family_own_pdf',status=r.status_code,body=r.json() if r.status_code!=200 else {})
r=client.get('/api/drugs/records',params={'elder_id':elder.id})
record('family_drug_records',status=r.status_code,count=len(r.json()) if isinstance(r.json(),list) else None)
print('DONE',flush=True)

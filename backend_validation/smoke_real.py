"""Real OCR and local AI smoke test with synthetic image and isolated database."""
import io
import json
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from PIL import Image, ImageDraw, ImageFont
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
import main
from api import reports
from db.database import Base, get_db
from db.models import User
from core.security import create_access_token

engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
Base.metadata.create_all(engine)
sessions = sessionmaker(bind=engine)
with sessions() as db:
    user = User(role='elder', phone='synthetic', password_hash='test', nickname='Test')
    db.add(user)
    db.commit()
    token = create_access_token(user)

def isolated_db():
    with sessions() as db:
        yield db

image = Image.new('RGB', (1600, 400), 'white')
draw = ImageDraw.Draw(image)
font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 48)
draw.text((50, 50), 'GLU    7.2    mmol/L    3.9-6.1', font=font, fill='black')
draw.text((50, 180), 'ALT    20    U/L    0-40', font=font, fill='black')
image.save('backend_validation/synthetic_report.png')
buf = io.BytesIO()
image.save(buf, 'PNG')
main.app.dependency_overrides[get_db] = isolated_db
try:
    with tempfile.TemporaryDirectory() as uploads, \
         patch.object(main, 'init_db'), patch.object(main, 'start_scheduler'), \
         patch.object(reports, 'UPLOAD_DIR', uploads), TestClient(main.app) as client:
        assert client.get('/').status_code == 200
        assert main.app.state.ocr_ready, main.app.state.ocr_error
        r = client.post('/api/reports/upload', headers={'Authorization': 'Bearer ' + token},
                        files={'file': ('synthetic.bin', buf.getvalue(), 'application/octet-stream')})
        assert r.status_code == 200, r.text
        body = r.json()
        Path('backend_validation/real_pipeline.json').write_text(json.dumps(body, ensure_ascii=False, indent=2), encoding='utf-8')
        rows = {item['code']: item for item in body['metrics']}
        assert rows['GLU']['status'] == 'high', rows
        assert rows['ALT']['status'] == 'normal', rows
        history = client.get('/api/reports', headers={'Authorization': 'Bearer ' + token}).json()
        assert history[0]['metrics'] == body['metrics']
        assert body['advice_text']
        print('Real startup, OCR, report upload, local AI and history: passed')
finally:
    main.app.dependency_overrides.clear()
    engine.dispose()

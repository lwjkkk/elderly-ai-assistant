r"""Real bge, cloud text generation and OCR/API smoke; isolated databases only.

Run with D:\python\python.exe -X utf8 -m backend_validation.real_pipeline_20261022.
No model response, OCR result or embedding is mocked. Configuration paths and
the request database are redirected to temporary directories.
"""
import json
import os
import tempfile
import time
from pathlib import Path
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from api import reports, routes, sync
from config import settings
from core import agent, rag_hybrid, rag_indexer
from core.security import create_access_token
from db.database import Base, get_db
from db.models import User


def main():
    os.environ.setdefault('HF_HUB_OFFLINE', '1')
    evidence = {'model': settings.QWEN_MODEL_NAME, 'checks': [], 'responses': {}}
    with tempfile.TemporaryDirectory(prefix='silver-real-') as directory:
        vector_db = str(Path(directory) / 'vectors.db')
        print('Loading actual local bge model...', flush=True)
        embedder = rag_indexer.build_embedder()
        stats = rag_hybrid.ensure_index(vector_db, embedder)
        evidence['index_stats'] = stats
        print('Actual bge index:', stats, flush=True)
        found = rag_hybrid.hybrid_retrieve('高血压怎么控制', db_path=vector_db, embedder=embedder)
        assert found['results'], found
        assert all(r['document_id'] and r['chunk_id'] and r['document_version'] for r in found['results'])
        evidence['checks'].append('real_embedding_and_chunk_metadata')

        app = FastAPI()
        for router in (reports.router, routes.router, sync.router):
            app.include_router(router)
        engine = create_engine('sqlite://', poolclass=StaticPool,
                               connect_args={'check_same_thread': False})
        Base.metadata.create_all(engine)
        factory = sessionmaker(bind=engine)
        with factory() as db:
            user = User(id=1, role='elder', nickname='脱敏样例', phone='synthetic',
                        password_hash='x', birth_ym='1970-01')
            db.add(user)
            db.commit()
            token = create_access_token(user)
        def database():
            with factory() as db:
                yield db
        app.dependency_overrides[get_db] = database
        with patch.object(rag_indexer, 'get_default_db_path', return_value=vector_db), \
             patch.object(reports, 'UPLOAD_DIR', directory), \
             patch.object(agent, '_RAG_EMBEDDER', embedder), TestClient(app) as client:
            for question in ('高血压老人平时饮食要注意什么？', '微信怎么发红包？', '胸痛是不是心梗？'):
                start = time.monotonic()
                response = client.post('/api/chat/tiered', json={'question': question})
                assert response.status_code == 200, response.text
                body = response.json()
                assert body['fallback_reason'] != 'answer_generation_error', body
                assert body['answer'] and body['steps'] and body['schema_version'] == 2
                assert body['elder_view'] and body['family_view']
                assert body['module'] == ('phone' if '微信' in question else 'health'), body
                if body['module'] == 'health':
                    assert body['source'] == 'llm', body
                    assert body['parts']['meaning'], body
                    assert body['elder_view']['seek'] == body['family_view']['seek'], body
                    assert all(rag_hybrid._matches_query_focus(question, s['title'], s['excerpt'])
                               for s in body['sources']), body
                    if '胸痛' in question:
                        assert '立即拨打120' in body['elder_view']['seek'], body
                else:
                    assert body['view']['seek'] == '', body
                assert body['sources'] and all(s['chunk_id'] for s in body['sources']), body
                evidence['responses'][question] = body
                evidence['checks'].append('real_chat:' + question)
                print('Actual chat completed: %.1fs %s' % (time.monotonic() - start, question), flush=True)

            sample = Path(__file__).parent / 'sample_report.png'
            start = time.monotonic()
            upload = client.post('/api/reports/upload',
                headers={'Authorization': 'Bearer ' + token},
                files={'file': ('report.png', sample.read_bytes(), 'image/png')})
            assert upload.status_code == 200, upload.text
            body = upload.json()
            assert body['ocr_text'] and body['advice_text'] and body['metrics'], body
            bp = next(m for m in body['metrics'] if m['code'] == '血压')
            assert bp['result'] is None and bp['result_text'] == '120/80', bp
            headers = {'Authorization': 'Bearer ' + token}
            history = client.get('/api/reports', headers=headers).json()[0]
            synced = client.get('/api/sync', headers=headers).json()['reports'][0]
            assert body['metrics'] == history['metrics'] == synced['metrics']
            evidence['responses']['report'] = body
            evidence['checks'].append('real_ocr_upload_advice_history_sync')
            print('Actual OCR/report/model/history/sync completed: %.1fs' % (time.monotonic() - start), flush=True)
        engine.dispose()
    output = Path(__file__).parent / 'real_pipeline_20261022_result.json'
    output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')
    print('PASS', evidence['checks'], flush=True)


if __name__ == '__main__':
    main()

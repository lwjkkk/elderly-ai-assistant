"""Child-process bootstrap for disposable legacy/manual script execution."""
import os
from pathlib import Path
import runpy
import socket
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
if __name__ == '__main__':
    target, *arguments = sys.argv[1:]
    if os.environ.get('SILVER_ALLOW_EXTERNAL') != '1':
        connect = socket.socket.connect
        def local_only(sock, address):
            if isinstance(address, tuple) and address[0] not in ('127.0.0.1', '::1', 'localhost'):
                raise RuntimeError('Public network disabled; explicitly enable --allow-external for live tests')
            return connect(sock, address)
        socket.socket.connect = local_only
    # RAG uses an absolute repository default, so changing cwd alone is insufficient.
    from core import rag_indexer
    rag_indexer.get_default_db_path = lambda: str(Path.cwd() / 'test_knowledge_vectors.db')
    sys.argv = [target, *arguments]
    runpy.run_path(target, run_name='__main__')

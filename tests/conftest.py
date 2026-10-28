"""Default regressions isolate working files and reject public network access."""
import os
import socket
from pathlib import Path
import pytest

os.environ.setdefault('HF_HUB_OFFLINE', '1')
os.environ.setdefault('TRANSFORMERS_OFFLINE', '1')

@pytest.fixture(scope='session', autouse=True)
def isolated_test_process(tmp_path_factory):
    previous = Path.cwd()
    sandbox = tmp_path_factory.mktemp('backend-work')
    (sandbox / 'backend_validation').mkdir()
    os.chdir(sandbox)
    connect = socket.socket.connect
    def local_only(sock, address):
        if isinstance(address, tuple) and address[0] not in ('127.0.0.1', '::1', 'localhost'):
            raise AssertionError('Offline regression attempted public network access')
        return connect(sock, address)
    socket.socket.connect = local_only
    try:
        yield
    finally:
        socket.socket.connect = connect
        os.chdir(previous)

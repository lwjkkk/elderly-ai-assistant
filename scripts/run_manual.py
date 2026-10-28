"""Run an explicitly selected script with disposable SQLite and output files."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--allow-external', action='store_true', help='Explicitly enable a real-model integration script')
    parser.add_argument('script', help='Path relative to tests/, e.g. manual/verify_profile.py')
    parser.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    target = (ROOT / 'tests' / args.script).resolve()
    if not target.is_relative_to(ROOT / 'tests') or not target.is_file() or target.suffix != '.py':
        parser.error('Select an existing Python script inside tests/')
    if target.is_relative_to(ROOT / 'tests/integration') and not args.allow_external:
        parser.error('Real-service scripts require --allow-external; synthetic test input only')
    env = dict(os.environ, PYTHONPATH=str(ROOT), PYTHONDONTWRITEBYTECODE='1', SILVER_MANUAL_SANDBOX='1',
               SILVER_ALLOW_EXTERNAL='1' if args.allow_external else '0')
    with tempfile.TemporaryDirectory(prefix='silver-manual-') as temp:
        for name in ('docs', 'backend_validation', 'uploads'):
            (Path(temp) / name).mkdir()
        print('Disposable working directory:', temp, flush=True)
        raise SystemExit(subprocess.call([sys.executable, str(ROOT / 'scripts/manual_entry.py'), str(target),
                                         *args.arguments], cwd=temp, env=env))

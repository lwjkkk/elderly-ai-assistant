"""Initialize/migrate an explicitly selected SQLite database idempotently."""
import argparse
from pathlib import Path
import sys
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, required=True, help='Target SQLite file, never inferred from the shell directory')
    args = parser.parse_args()
    destination = args.database.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    import db.database as database
    engine = create_engine('sqlite:///' + destination.as_posix(), connect_args={'check_same_thread': False})
    database.engine = engine
    database.SessionLocal = sessionmaker(bind=engine)
    try:
        database.init_db()
        print('Initialized:', destination)
    finally:
        engine.dispose()

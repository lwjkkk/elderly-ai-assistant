# 数据库连接层
# 作用：创建数据库引擎、会话工厂和所有表的基类 Base。
# 改版方案：SQLite 先行（本地一个文件即可跑通），后期再平滑换成 MySQL。

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker, declarative_base

# SQLite 数据库文件，会在项目根目录生成 elderly.db
SQLALCHEMY_DATABASE_URL = "sqlite:///./elderly.db"

# check_same_thread=False：FastAPI 多线程访问 SQLite 时必须关闭同线程限制
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
)

# 会话工厂：每个请求创建一个独立会话，请求结束关闭
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 所有 ORM 表模型都要继承这个 Base
Base = declarative_base()


def get_db():
    """FastAPI 依赖注入函数：给接口提供数据库会话，用完自动关闭。"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """建表：导入模型后调用，让 Base 知道有哪些表，再一次性创建。"""
    # 必须先 import models，否则 Base 不知道表的存在
    from db import models  # noqa: F401
    Base.metadata.create_all(bind=engine)
    # 对已存在的旧库补建新增列（SQLite 用 ALTER TABLE，幂等：已存在则跳过）
    # 注意：补列必须在建索引之前，否则索引引用不存在的列会报错
    _add_column_if_missing(
        "users",
        "sync_summary_to_family",
        "ALTER TABLE users ADD COLUMN sync_summary_to_family BOOLEAN DEFAULT 1 NOT NULL",
    )
    _add_column_if_missing(
        "medications",
        "start_date",
        "ALTER TABLE medications ADD COLUMN start_date VARCHAR(10)",
    )
    # 用户资料（多端同步）：性别/出生年月/头像
    _add_column_if_missing(
        "users",
        "gender",
        "ALTER TABLE users ADD COLUMN gender VARCHAR(10)",
    )
    _add_column_if_missing(
        "users",
        "birth_ym",
        "ALTER TABLE users ADD COLUMN birth_ym VARCHAR(7)",
    )
    _add_column_if_missing(
        "users",
        "avatar_url",
        "ALTER TABLE users ADD COLUMN avatar_url VARCHAR(500)",
    )
    # 隐私保护按开启时间生效：记录开启时刻，家属只能看到之前的记录
    _add_column_if_missing(
        "users",
        "privacy_enabled_at",
        "ALTER TABLE users ADD COLUMN privacy_enabled_at DATETIME",
    )
    # 增量同步支持：药品更新时间、体征入库时间
    # SQLite 不支持 ALTER TABLE 加非恒定默认值，用 NULL 建列后再回填
    _add_column_if_missing(
        "medications",
        "updated_at",
        "ALTER TABLE medications ADD COLUMN updated_at DATETIME",
    )
    _add_column_if_missing(
        "vitals",
        "created_at",
        "ALTER TABLE vitals ADD COLUMN created_at DATETIME",
    )
    _add_column_if_missing(
        "vitals",
        "measurement_context",
        "ALTER TABLE vitals ADD COLUMN measurement_context VARCHAR(20)",
    )
    _add_column_if_missing(
        "vitals", "draft_session_id",
        "ALTER TABLE vitals ADD COLUMN draft_session_id INTEGER",
    )
    _add_column_if_missing(
        "vital_alerts",
        "measurement_context",
        "ALTER TABLE vital_alerts ADD COLUMN measurement_context VARCHAR(20)",
    )
    _add_column_if_missing("vital_alerts", "vital_id", "ALTER TABLE vital_alerts ADD COLUMN vital_id INTEGER")
    _add_column_if_missing("vital_alerts", "threshold_version", "ALTER TABLE vital_alerts ADD COLUMN threshold_version VARCHAR(40)")
    _add_column_if_missing("vital_alerts", "measured_at", "ALTER TABLE vital_alerts ADD COLUMN measured_at DATETIME")
    _add_column_if_missing(
        "vital_draft_conversations",
        "measurement_context",
        "ALTER TABLE vital_draft_conversations ADD COLUMN measurement_context VARCHAR(20) DEFAULT 'unknown'",
    )
    _add_column_if_missing("vital_draft_conversations", "confirmed_vital_id", "ALTER TABLE vital_draft_conversations ADD COLUMN confirmed_vital_id INTEGER")
    _add_column_if_missing("vital_draft_conversations", "version", "ALTER TABLE vital_draft_conversations ADD COLUMN version INTEGER NOT NULL DEFAULT 1")
    _add_column_if_missing("vital_draft_conversations", "subject_label", "ALTER TABLE vital_draft_conversations ADD COLUMN subject_label VARCHAR(80)")
    _add_column_if_missing("vital_draft_conversations", "subject_confirmed", "ALTER TABLE vital_draft_conversations ADD COLUMN subject_confirmed BOOLEAN NOT NULL DEFAULT 1")
    _add_column_if_missing("notification_outbox", "claimed_at", "ALTER TABLE notification_outbox ADD COLUMN claimed_at DATETIME")
    # Partial unique indexes safely upgrade existing SQLite databases and allow NULL for legacy/manual records.
    with engine.begin() as conn:
        if "vitals" in inspect(engine).get_table_names():
            conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_vitals_draft_session ON vitals(draft_session_id) WHERE draft_session_id IS NOT NULL"))
        if "vital_alerts" in inspect(engine).get_table_names():
            conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_vital_alert_vital ON vital_alerts(vital_id) WHERE vital_id IS NOT NULL"))
    # 回填历史数据：把已有记录的 updated_at/created_at 设为其 created_at/measured_at
    _backfill_column(
        "medications", "updated_at",
        "UPDATE medications SET updated_at = created_at WHERE updated_at IS NULL",
    )
    _backfill_column(
        "vitals", "created_at",
        "UPDATE vitals SET created_at = measured_at WHERE created_at IS NULL",
    )
    # 补建索引（列已存在后安全创建）
    for table in Base.metadata.tables.values():
        for idx in table.indexes:
            idx.create(bind=engine, checkfirst=True)
    for column, sql_type in [('transcript', 'TEXT'), ('summary', 'TEXT'), ('summary_status', 'VARCHAR(20)'), ('summary_error', 'VARCHAR(200)')]:
        _add_column_if_missing('consult_records', column, f'ALTER TABLE consult_records ADD COLUMN {column} {sql_type}')


def _add_column_if_missing(table: str, column: str, ddl: str):
    """若表已存在但缺少指定列，则执行 ALTER TABLE 补列（SQLite）。"""
    insp = inspect(engine)
    if table not in insp.get_table_names():
        return
    cols = {c["name"] for c in insp.get_columns(table)}
    if column not in cols:
        with engine.begin() as conn:
            conn.execute(text(ddl))


def _backfill_column(table: str, column: str, sql: str):
    """对指定列执行回填 SQL（仅在列存在且有 NULL 时才实际更新）。"""
    insp = inspect(engine)
    if table not in insp.get_table_names():
        return
    cols = {c["name"] for c in insp.get_columns(table)}
    if column in cols:
        with engine.begin() as conn:
            conn.execute(text(sql))

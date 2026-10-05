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
    # 对已存在的旧库补建新增索引（create_all 不会改已存在的表）
    for table in Base.metadata.tables.values():
        for idx in table.indexes:
            idx.create(bind=engine, checkfirst=True)
    # 对已存在的旧库补建新增列（SQLite 用 ALTER TABLE，幂等：已存在则跳过）
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


def _add_column_if_missing(table: str, column: str, ddl: str):
    """若表已存在但缺少指定列，则执行 ALTER TABLE 补列（SQLite）。"""
    insp = inspect(engine)
    if table not in insp.get_table_names():
        return
    cols = {c["name"] for c in insp.get_columns(table)}
    if column not in cols:
        with engine.begin() as conn:
            conn.execute(text(ddl))

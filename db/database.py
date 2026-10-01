# 数据库连接层
# 作用：创建数据库引擎、会话工厂和所有表的基类 Base。
# 改版方案：SQLite 先行（本地一个文件即可跑通），后期再平滑换成 MySQL。

from sqlalchemy import create_engine
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

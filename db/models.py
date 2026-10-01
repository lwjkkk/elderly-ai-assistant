# ORM 表模型：用 Python 类描述数据库里的表
# Day1 先建两张表：users（账号）和 family_bindings（老人/家属绑定关系）

from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, Date, JSON, func
from db.database import Base


class User(Base):
    """用户表：老人和家属都存在这里，用 role 区分身份。"""
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    # 角色：elder=老人，family=家属（子女）
    role = Column(String(10), nullable=False)
    # 手机号：登录账号，必须唯一
    phone = Column(String(20), unique=True, index=True, nullable=False)
    # 密码哈希：只存加密后的结果，绝不存明文密码
    password_hash = Column(String(255), nullable=False)
    # 昵称：绑定后双方在"我的"页能看到对方昵称
    nickname = Column(String(50), nullable=False)


class FamilyBinding(Base):
    """绑定关系表：记录哪位家属绑定了哪位老人。"""
    __tablename__ = "family_bindings"

    id = Column(Integer, primary_key=True, index=True)
    # 老人用户 id
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    # 家属用户 id：刚生成邀请码还没人接受时为空，接受绑定时再填入
    family_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    # 状态：pending=待绑定，active=已绑定，unbound=已解绑，expired=邀请码已过期
    status = Column(String(20), default="pending", nullable=False)
    # 邀请码：老人生成、家属输入，用来建立绑定
    invite_code = Column(String(20), index=True, nullable=False)
    created_at = Column(DateTime, server_default=func.now())


class Medication(Base):
    """药品表：记录给某位老人录入的药品及服药时间。"""
    __tablename__ = "medications"

    id = Column(Integer, primary_key=True, index=True)
    # 归属的老人
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    # 录入者：老人自己或绑定家属（家属可代录）
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String(100), nullable=False)          # 药品名，如 阿司匹林
    dosage = Column(String(50), nullable=False)         # 剂量，如 1片 / 100mg
    frequency = Column(String(50), nullable=False)      # 频次，如 每日1次 / 每日3次
    # 服药时间点列表，如 ["08:00"] 或 ["08:00","12:00","18:00"]
    times = Column(JSON, nullable=False, default=list)
    created_at = Column(DateTime, server_default=func.now())


class MedicationLog(Base):
    """服药记录表：每个药品在某天某个时间点的服药状态。"""
    __tablename__ = "medication_logs"

    id = Column(Integer, primary_key=True, index=True)
    medication_id = Column(Integer, ForeignKey("medications.id"), nullable=False)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    date = Column(String(10), nullable=False, index=True)   # 日期 YYYY-MM-DD
    slot = Column(String(10), nullable=False)              # 时间点，如 08:00
    # 状态：pending 待服，taken 已服，missed 漏服
    status = Column(String(10), default="pending", nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class Vitals(Base):
    """体征记录表：血压、血糖、心率、体重。"""
    __tablename__ = "vitals"

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    # 类型：bp=血压, bs=血糖, hr=心率, weight=体重
    type = Column(String(10), nullable=False)
    # 血压专用：收缩压/舒张压（mmHg），其他类型留空
    systolic = Column(Integer, nullable=True)
    diastolic = Column(Integer, nullable=True)
    # 通用数值：血糖(mmol/L)、心率(bpm)、体重(kg)
    value = Column(String(20), nullable=True)
    measured_at = Column(DateTime, server_default=func.now())


class ConsultRecord(Base):
    """问诊录音表：记录老人就诊录音。"""
    __tablename__ = "consult_records"

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    audio_url = Column(String(500), nullable=False)   # 本地路径或对象存储 URL
    duration = Column(Integer, nullable=True)          # 录音时长（秒）
    hospital = Column(String(100), nullable=True)      # 医院名
    doctor = Column(String(50), nullable=True)         # 医生名
    created_at = Column(DateTime, server_default=func.now())

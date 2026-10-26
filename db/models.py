# ORM 表模型：用 Python 类描述数据库里的表
# Day1 先建两张表：users（账号）和 family_bindings（老人/家属绑定关系）

from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, Date, JSON, Boolean, Float, UniqueConstraint, func
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
    # 性别：男/女/空字符串（空=未设置，资料编辑页可多端同步）
    gender = Column(String(10), nullable=True, default=None)
    # 出生年月：YYYY-MM（资料编辑页可多端同步）
    birth_ym = Column(String(7), nullable=True, default=None)
    # 头像 URL：上传后存文件，返回相对路径（资料编辑页可多端同步）
    avatar_url = Column(String(500), nullable=True, default=None)
    # 隐私开关：是否把对话摘要同步给家属。1=同步（默认），0=不同步。仅老人本人可改。
    sync_summary_to_family = Column(Boolean, default=True, nullable=False)
    # 隐私开启时间：开启时记录当前时间，关闭时清空。家属只能看到此时间之前产生的摘要/查药记录。
    privacy_enabled_at = Column(DateTime, nullable=True, default=None)


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
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    # 录入者：老人自己或绑定家属（家属可代录）
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String(100), nullable=False)          # 药品名，如 阿司匹林
    dosage = Column(String(50), nullable=False)         # 剂量，如 1片 / 100mg
    frequency = Column(String(50), nullable=False)      # 频次，如 每日1次 / 每日3次
    # 服药时间点列表，如 ["08:00"] 或 ["08:00","12:00","18:00"]
    times = Column(JSON, nullable=False, default=list)
    # 开始用药日期（YYYY-MM-DD），可空；用于定时推送/按日统计对齐
    start_date = Column(String(10), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    # 更新时间：修改药品信息时自动刷新，用于增量同步检测变更
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class MedicationLog(Base):
    """服药记录表：每个药品在某天某个时间点的服药状态。"""
    __tablename__ = "medication_logs"
    __table_args__ = (
        UniqueConstraint("medication_id", "date", "slot", name="uq_med_log_slot"),
    )

    id = Column(Integer, primary_key=True, index=True)
    medication_id = Column(Integer, ForeignKey("medications.id"), nullable=False, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    date = Column(String(10), nullable=False, index=True)   # 日期 YYYY-MM-DD
    slot = Column(String(10), nullable=False)              # 时间点，如 08:00
    # 状态：pending 待服，taken 已服，missed 漏服
    status = Column(String(10), default="pending", nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class Vitals(Base):
    """体征记录表：血压、血糖、心率、体重。"""
    __tablename__ = "vitals"

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    # 类型：bp=血压, bs=血糖, hr=心率, weight=体重
    type = Column(String(10), nullable=False)
    # 血压专用：收缩压/舒张压（mmHg），其他类型留空
    systolic = Column(Integer, nullable=True)
    diastolic = Column(Integer, nullable=True)
    # 通用数值：血糖(mmol/L)、心率(bpm)、体重(kg)
    value = Column(String(20), nullable=True)
    # 血糖测量场景：fasting/postprandial/random/unknown；其他体征为空。
    measurement_context = Column(String(20), nullable=True)
    # 测量时间：用户填写的实际测量时间
    measured_at = Column(DateTime, server_default=func.now(), index=True)
    # 入库时间：记录创建时间，用于增量同步（补录历史数据时 measured_at 在过去但 created_at 是当前）
    created_at = Column(DateTime, server_default=func.now(), index=True)
    # A draft session can commit at most one official vital record.
    draft_session_id = Column(Integer, ForeignKey("vital_draft_conversations.id"), nullable=True, unique=True)


class ConsultRecord(Base):
    """问诊录音表：记录老人就诊录音。"""
    __tablename__ = "consult_records"

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    audio_url = Column(String(500), nullable=False)   # 本地路径或对象存储 URL
    duration = Column(Integer, nullable=True)          # 录音时长（秒）
    hospital = Column(String(100), nullable=True)      # 医院名
    doctor = Column(String(50), nullable=True)         # 医生名
    created_at = Column(DateTime, server_default=func.now())
    transcript = Column(String, nullable=True)
    summary = Column(String, nullable=True)
    summary_status = Column(String(20), nullable=True)
    summary_error = Column(String(200), nullable=True)


class HealthReport(Base):
    """体检报告表：上传体检单图片，OCR 识别 + AI 建议（不做诊断）。"""
    __tablename__ = "health_reports"

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    image_url = Column(String(500), nullable=True)     # 体检单图片保存路径
    ocr_text = Column(String, nullable=True)           # OCR 识别出的指标文字
    ocr_details = Column(JSON, nullable=True)          # 坐标、置信度及持久化指标
    advice_text = Column(String, nullable=True)        # AI 大白话建议
    created_at = Column(DateTime, server_default=func.now())


class ReportJob(Base):
    """报告后台任务。阶段结果持久化，进程重启后可明确告知中断。"""
    __tablename__ = "report_jobs"

    id = Column(String(32), primary_key=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    requested_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    status = Column(String(20), nullable=False, default="queued", index=True)
    image_path = Column(String(500), nullable=True)
    ocr_text = Column(String, nullable=True)
    metrics = Column(JSON, nullable=True)
    timings = Column(JSON, nullable=True)
    ocr_details = Column(JSON, nullable=True)
    report_id = Column(Integer, ForeignKey("health_reports.id"), nullable=True)
    error = Column(String(500), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class SymptomCheck(Base):
    """症状自查表：输入症状描述，AI 建议 + 风险分级。"""
    __tablename__ = "symptom_checks"

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    input_text = Column(String, nullable=False)        # 老人描述的症状
    advice_text = Column(String, nullable=True)        # AI 建议
    answer_data = Column(JSON, nullable=True)         # 当次来源快照，历史读取不重新检索
    # 风险等级：green=可居家观察，yellow=建议尽快就医，red=立即就医/急诊
    risk = Column(String(10), nullable=False)
    created_at = Column(DateTime, server_default=func.now())


class ChatSummary(Base):
    """对话摘要表：从日常问答中提炼的记录，可按需同步给家属。

    category 四类：drug=查药, med=用药, selfcheck=自查, consult=咨询。
    risk 仅 selfcheck 类可能有（green/yellow/red）。
    synced：是否已推送给家属（预留，当前读取口按同步开关直接过滤）。
    """
    __tablename__ = "chat_summaries"

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    category = Column(String(20), nullable=False, index=True)
    question = Column(String, nullable=False)          # 老人原始问题
    summary = Column(String, nullable=False)           # 提炼的一句话记录
    risk = Column(String(10), nullable=True)           # selfcheck 类风险等级
    module = Column(String(20), nullable=True)         # 来源模块 phone/services/daily_life/health
    created_at = Column(DateTime, server_default=func.now(), index=True)
    synced = Column(Boolean, default=False, nullable=False)


class DrugQuery(Base):
    """查药记录表：拍照查药 / 按名查药的历史，供家属端查看。"""
    __tablename__ = "drug_queries"

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    kind = Column(String(10), nullable=False)          # image=拍照, name=按名
    input_text = Column(String, nullable=True)         # 拍照时的 OCR 原文 / 按名时的药名
    ocr_text = Column(String, nullable=True)           # OCR 识别文字（拍照类）
    explanation = Column(String, nullable=True)        # AI 大白话解读
    disclaimer = Column(String, nullable=True)         # 免责声明
    created_at = Column(DateTime, server_default=func.now(), index=True)


class FamilyMessage(Base):
    """家人消息表：老人/家属双端互发文字或健康消息，持久化存库。"""
    __tablename__ = "family_messages"

    id = Column(Integer, primary_key=True, index=True)
    binding_id = Column(Integer, ForeignKey("family_bindings.id"), nullable=False, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    # 消息类型：text=文字, health=健康摘要/用药提醒等结构化内容
    kind = Column(String(10), nullable=False)
    content = Column(JSON, nullable=False)
    created_at = Column(DateTime, server_default=func.now(), index=True)


class VitalAlert(Base):
    """体征异常事件（#9，10.27 新增）：血压/血糖超阈值时持久化记录，供老人/授权家属端可查、可追踪。

    记录触发当次数值与阈值来源，配合 services/push 向 active 绑定家属发送提示（推送记录在内存列表，可追踪）。
    事件仅供提示，不替代诊断；阈值口径由 C 主测复核。
    """
    __tablename__ = "vital_alerts"

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    vital_type = Column(String(10), nullable=False)   # bp / bs
    systolic = Column(Integer, nullable=True)
    diastolic = Column(Integer, nullable=True)
    value = Column(Float, nullable=True)
    measurement_context = Column(String(20), nullable=True)
    level = Column(String(10), nullable=False)        # high / low / mixed
    message = Column(String, nullable=True)
    source = Column(String, nullable=True)            # 阈值来源说明
    vital_id = Column(Integer, ForeignKey("vitals.id"), nullable=True, unique=True, index=True)
    threshold_version = Column(String(40), nullable=True)
    measured_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now(), index=True)


class VitalDraftConversation(Base):
    """体征口述录入会话（#8 多轮追问状态，10.23 新增）。

    从语音/口述文本逐轮收集体征草稿：缺字段时保存会话并追问，字段补充后合并，
    status=collecting 时不写入 vitals；只有 confirm 才复用现有 POST /api/vitals 落库，
    未确认一律不写库（cancel/超时/重进页面都可恢复或作废）。
    status: collecting=收集中, ready=信息齐全待确认, confirmed=已确认入库, cancelled=已取消
    """
    __tablename__ = "vital_draft_conversations"

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    # 体征类型：bp/bs/hr/weight；未识别出时为 None
    type = Column(String(10), nullable=True)
    systolic = Column(Integer, nullable=True)
    diastolic = Column(Integer, nullable=True)
    value = Column(Float, nullable=True)
    unit = Column(String(20), nullable=True)
    measurement_context = Column(String(20), nullable=True, default="unknown")
    measured_text = Column(String(50), nullable=True)
    measured_at = Column(DateTime, nullable=True)
    raw_text = Column(String, nullable=True)
    # 缺失字段列表（JSON）：type/systolic/diastolic/value
    missing = Column(JSON, nullable=True, default=list)
    # 上一次追问文本
    last_question = Column(String, nullable=True)
    status = Column(String(20), nullable=False, default="collecting")
    confirmed_vital_id = Column(Integer, ForeignKey("vitals.id"), nullable=True, unique=True)
    version = Column(Integer, nullable=False, default=1)
    subject_label = Column(String(80), nullable=True)
    subject_confirmed = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class IdempotencyRecord(Base):
    """Stores confirmation replay keys and canonical request/result fingerprints."""
    __tablename__ = "idempotency_records"
    __table_args__ = (UniqueConstraint("user_id", "key", name="uq_idempotency_user_key"),)

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    key = Column(String(120), nullable=False)
    request_hash = Column(String(64), nullable=False)
    response_json = Column(JSON, nullable=False)
    created_at = Column(DateTime, server_default=func.now(), index=True)


class NotificationOutbox(Base):
    """Durable notification delivery queue; delivery failures never undo saved health data."""
    __tablename__ = "notification_outbox"
    __table_args__ = (UniqueConstraint("dedupe_key", name="uq_notification_dedupe_key"),)

    id = Column(Integer, primary_key=True, index=True)
    elder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    receiver_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    alert_id = Column(Integer, ForeignKey("vital_alerts.id"), nullable=True, index=True)
    channel = Column(String(30), nullable=False, default="in_app")
    status = Column(String(20), nullable=False, default="pending")
    retry_count = Column(Integer, nullable=False, default=0)
    claimed_at = Column(DateTime, nullable=True)
    # NULL keeps existing vital/emergency rows compatible with the old queue.
    kind = Column(String(30), nullable=True)
    medication_id = Column(Integer, nullable=True, index=True)
    scheduled_for = Column(DateTime, nullable=True)  # UTC, timezone-naive as other persisted times
    expires_at = Column(DateTime, nullable=True)
    last_error = Column(String(500), nullable=True)
    title = Column(String(120), nullable=False)
    content = Column(String, nullable=False)
    dedupe_key = Column(String(160), nullable=False)
    created_at = Column(DateTime, server_default=func.now(), index=True)
    delivered_at = Column(DateTime, nullable=True)

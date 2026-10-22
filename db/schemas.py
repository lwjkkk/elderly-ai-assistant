# Pydantic 校验模型：负责校验请求体长什么样、返回体长什么样
# 注意和 models.py 的区别：models 对应数据库表，schemas 对应接口的输入输出

from datetime import datetime, timezone

from pydantic import BaseModel, Field, field_serializer

from core.disclaimer import HEALTH_DISCLAIMER


# ---------- 账号鉴权 ----------

# 中国大陆手机号：1 开头、第二位 3-9、共 11 位数字
PHONE_PATTERN = r"^1[3-9]\d{9}$"


class UserCreate(BaseModel):
    """注册请求体"""
    phone: str = Field(..., pattern=PHONE_PATTERN, description="11位手机号，作为登录账号")
    password: str = Field(..., min_length=6, description="密码，至少6位")
    nickname: str = Field(..., description="昵称")
    role: str = Field(..., description="角色：elder 老人 / family 家属")


class UserOut(BaseModel):
    """返回给前端的用户信息（不含密码）"""
    id: int
    phone: str
    nickname: str
    role: str

    class Config:
        from_attributes = True  # 允许直接从 ORM 对象转换


class UserProfileUpdate(BaseModel):
    """资料编辑请求体：全可选，只传改了的字段"""
    nickname: str | None = Field(default=None, max_length=50, description="昵称")
    gender: str | None = Field(default=None, description="性别：男/女/空字符串(空=未设置)")
    birth_ym: str | None = Field(default=None, description="出生年月，格式 YYYY-MM")
    avatar_base64: str | None = Field(default=None, description="圆形裁剪后的头像图 base64(jpg)")


class UserProfileOut(BaseModel):
    """资料编辑后一次性返回完整资料，前端用它刷新本地"""
    id: int
    nickname: str
    gender: str | None = None
    birth_ym: str | None = None
    avatar_url: str | None = None
    # 10.26 #5 年龄分层：周岁、分层、是否强制分享（供前端隐藏/显示隐私控件）
    age: int | None = None
    age_tier: str | None = None      # senior / younger / unknown
    forced_share: bool = False       # True=满60周岁强制分享给子女

    class Config:
        from_attributes = True


class LoginRequest(BaseModel):
    """登录请求体"""
    phone: str = Field(..., pattern=PHONE_PATTERN, description="11位手机号")
    password: str


class SendSmsRequest(BaseModel):
    """获取验证码请求体（答辩演示：验证码打印到控制台，不真实下发短信）"""
    phone: str = Field(..., pattern=PHONE_PATTERN, description="11位手机号")


class SmsSent(BaseModel):
    """获取验证码返回体（不含验证码本身，验证码只在后端控制台打印）"""
    message: str
    expires_in: int = Field(default=300, description="验证码有效期（秒）")


class LoginByCodeRequest(BaseModel):
    """验证码登录请求体"""
    phone: str = Field(..., pattern=PHONE_PATTERN, description="11位手机号")
    code: str = Field(..., min_length=6, max_length=6, description="6位验证码")


class Token(BaseModel):
    """登录成功返回的令牌"""
    access_token: str
    token_type: str = "bearer"
    role: str
    nickname: str
    user_id: int


# ---------- 隐私开关 ----------

class PrivacyOut(BaseModel):
    """隐私开关返回体：是否把对话摘要同步给家属；附年龄分层与强制分享状态。"""
    sync_summary_to_family: bool
    age_tier: str | None = None      # senior / younger / unknown
    forced_share: bool = False       # 满60周岁强制分享，前端隐藏关闭按钮


class PrivacyUpdate(BaseModel):
    """隐私开关更新请求体"""
    sync_summary_to_family: bool


# ---------- 对话摘要 ----------

class ChatSummaryOut(BaseModel):
    """对话摘要返回体（家属端查看老人对话记录）"""
    id: int
    elder_id: int
    category: str            # drug / med / selfcheck / consult
    question: str
    summary: str
    risk: str | None = None
    module: str | None = None
    created_at: datetime | None = None

    class Config:
        from_attributes = True


# ---------- 查药记录 ----------

class DrugQueryOut(BaseModel):
    """查药记录返回体（家属端摘要展示）"""
    id: int
    elder_id: int
    kind: str                # image / name
    input_text: str | None = None
    ocr_text: str | None = None
    explanation: str | None = None
    disclaimer: str | None = None
    created_at: datetime | None = None

    class Config:
        from_attributes = True


# ---------- 绑定 ----------

class InviteOut(BaseModel):
    """老人生成邀请码的返回体"""
    invite_code: str


class BindAccept(BaseModel):
    """家属接受绑定的请求体"""
    invite_code: str


class BindingOut(BaseModel):
    """绑定关系返回体"""
    id: int
    elder_id: int
    family_id: int | None = None
    status: str
    invite_code: str

    class Config:
        from_attributes = True


# ---------- 用药管理 ----------

class MedicationCreate(BaseModel):
    """录入药品请求体"""
    name: str = Field(..., description="药品名")
    dosage: str = Field(..., description="剂量，如 1片")
    frequency: str = Field(..., description="频次，如 每日1次")
    times: list[str] = Field(..., description="服药时间点，如 ['08:00']")
    start_date: str | None = Field(None, description="开始用药日期 YYYY-MM-DD")
    elder_id: int | None = Field(None, description="家属代录时指定老人id；老人自己录可不填")


class MedicationUpdate(BaseModel):
    """修改药品请求体（所有字段可选，只改传的）；clear_start_date=True 表示清除开始日期"""
    name: str | None = None
    dosage: str | None = None
    frequency: str | None = None
    times: list[str] | None = None
    start_date: str | None = None
    clear_start_date: bool = False


class MedicationOut(BaseModel):
    id: int
    elder_id: int
    created_by: int
    name: str
    dosage: str
    frequency: str
    times: list[str]
    start_date: str | None = None

    class Config:
        from_attributes = True


class CheckInRequest(BaseModel):
    """打卡请求体"""
    medication_id: int
    slot: str = Field(..., description="时间点，如 08:00")
    date: str | None = Field(None, description="日期 YYYY-MM-DD，默认今天")


class LogOut(BaseModel):
    id: int
    medication_id: int
    elder_id: int
    date: str
    slot: str
    status: str

    class Config:
        from_attributes = True


class SlotStatus(BaseModel):
    slot: str
    status: str


class TodayMedication(BaseModel):
    """今日用药清单项"""
    medication_id: int
    name: str
    dosage: str
    slots: list[SlotStatus]


# ---------- 拍照查药 ----------

class DrugQuery(BaseModel):
    """拍照查药请求体"""
    image_base64: str = Field(..., description="药盒照片 base64")


class DrugNameQuery(BaseModel):
    """按药名查药请求体"""
    name: str = Field(..., description="药品名，如 阿司匹林")


class DrugResult(BaseModel):
    ocr_text: str
    explanation: str
    disclaimer: str


# ---------- 体征记录 ----------

class VitalsCreate(BaseModel):
    """录入体征请求体"""
    type: str = Field(..., description="类型：bp=血压, bs=血糖, hr=心率, weight=体重")
    systolic: int | None = Field(None, description="收缩压（血压时必填）")
    diastolic: int | None = Field(None, description="舒张压（血压时必填）")
    value: float | None = Field(None, description="通用数值：血糖/心率/体重")
    measurement_context: str | None = Field(
        "unknown",
        description="血糖测量场景：fasting=空腹、postprandial=餐后、random=随机、unknown=未注明；其他体征不适用",
    )
    measured_at: str | None = Field(None, description="记录日期/时间，如 2026-10-05 或 2026-10-05T09:12:00，默认当前时间")
    elder_id: int | None = Field(None, description="家属代录时指定老人id")


class VitalsOut(BaseModel):
    id: int
    elder_id: int
    type: str
    systolic: int | None = None
    diastolic: int | None = None
    value: float | None = None
    measurement_context: str | None = None
    measured_at: datetime | None = None
    notification_status: str | None = None
    disclaimer: str = HEALTH_DISCLAIMER

    @field_serializer("measured_at")
    def serialize_measured_at(self, value: datetime | None):
        if value is not None and value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat() if value else None

    class Config:
        from_attributes = True


class VitalAlertOut(BaseModel):
    """体征异常事件返回体（#9，10.27 新增）。"""
    id: int
    elder_id: int
    vital_type: str
    systolic: int | None = None
    diastolic: int | None = None
    value: float | None = None
    measurement_context: str | None = None
    level: str
    message: str | None = None
    source: str | None = None
    vital_id: int | None = None
    threshold_version: str | None = None
    measured_at: datetime | None = None
    created_at: datetime | None = None

    @field_serializer("measured_at", "created_at")
    def serialize_utc_timestamps(self, value: datetime | None):
        if value is not None and value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat() if value else None

    class Config:
        from_attributes = True


class VitalsSpokenParseRequest(BaseModel):
    """语音转写/口述体征草稿解析请求体（不落库）"""
    text: str = Field(..., description="语音转写文本/口述文本")
    hint_type: str | None = Field(None, description="可选提示类型：bp/bs/hr/weight，减少歧义")
    elder_id: int | None = Field(None, description="家属代录时指定老人id")


class VitalsSpokenDraftOut(BaseModel):
    """体征口述草稿返回体（不落库，前端编辑/确认后走 POST /api/vitals）"""
    hit: bool = Field(..., description="是否命中体征口述")
    type: str | None = None
    systolic: int | None = None
    diastolic: int | None = None
    value: float | None = None
    measurement_context: str | None = None
    unit: str | None = None
    measured_text: str | None = None
    measured_at: str | None = None
    raw_text: str | None = None
    confidence: float | None = None
    valid: bool | None = None
    errors: list[str] = []
    disclaimer: str = HEALTH_DISCLAIMER


class VitalsSpokenTurnRequest(BaseModel):
    """体征口述多轮会话：新一轮口述文本（#8，10.23）。"""
    text: str = Field(..., description="语音转写/口述文本")
    session_id: int | None = Field(None, description="体征会话id，续轮追问时传；新发起不传")
    hint_type: str | None = Field(None, description="可选提示类型：bp/bs/hr/weight")
    elder_id: int | None = Field(None, description="家属代录时指定老人id")


class VitalsSpokenEditRequest(BaseModel):
    version: int = Field(..., ge=1, description="读取草稿时返回的版本号，用于并发编辑保护")
    type: str | None = None
    systolic: int | None = None
    diastolic: int | None = None
    value: float | None = Field(None, allow_inf_nan=False)
    measurement_context: str | None = None
    measured_at: str | None = None
    timezone: str | None = Field(None, description="输入时间的 IANA 时区；默认 Asia/Shanghai")
    subject_label: str | None = None
    subject_confirmed: bool | None = None


class VitalDraftConfirmOut(VitalsOut):
    session_id: int
    status: str = "confirmed"
    confirmed_vital_id: int


class VitalsSpokenTurnOut(BaseModel):
    """体征口述会话返回体：草稿 + 缺失字段 + 追问文本（确认前不写库）。"""
    session_id: int
    status: str = Field(..., description="collecting/ready/confirmed/cancelled")
    missing: list[str] = Field(default_factory=list)
    question: str = ""
    can_confirm: bool = Field(..., description="信息齐全可确认")
    draft: dict = Field(default_factory=dict)
    elder_id: int | None = None
    subject_label: str | None = None
    subject_confirmed: bool = True
    version: int = 1
    confirmed_vital_id: int | None = None
    disclaimer: str = HEALTH_DISCLAIMER


class TrendPoint(BaseModel):
    """趋势图单个数据点"""
    date: str
    systolic: int | None = None
    diastolic: int | None = None
    value: float | None = None


# ---------- 问诊录音 ----------

class ConsultOut(BaseModel):
    id: int
    elder_id: int
    audio_url: str
    duration: int | None = None
    hospital: str | None = None
    doctor: str | None = None
    created_at: datetime | None = None

    class Config:
        from_attributes = True
    transcript: str | None = None
    summary: str | None = None
    summary_status: str | None = None
    summary_error: str | None = None


# ---------- 症状自查 ----------

class SymptomCreate(BaseModel):
    """症状自查请求体"""
    input_text: str = Field(..., description="症状描述，如 头疼、咳嗽两天")
    elder_id: int | None = Field(None, description="家属代提交时指定老人id")


class SymptomOut(BaseModel):
    id: int
    elder_id: int
    input_text: str
    advice_text: str | None = None
    risk: str                       # green / yellow / red
    created_at: datetime | None = None
    disclaimer: str = HEALTH_DISCLAIMER

    class Config:
        from_attributes = True


# ---------- 体检报告 ----------

class HealthReportOut(BaseModel):
    id: int
    elder_id: int
    image_url: str | None = None
    ocr_text: str | None = None
    advice_text: str | None = None
    # 上传、历史与同步共用该字段。歧义项保留原文并标为 unparsed。
    metrics: list[dict] = Field(
        default_factory=list,
        description="报告指标及 OCR 证据；status 为 normal/high/low/unparsed",
        examples=[[
            {
                "code": "GLU", "result": 6.2, "unit": "mmol/L",
                "lo": 3.9, "hi": 6.1, "status": "high",
                "ocr_text": "GLU 6.2 mmol/L 3.9-6.1",
                "source_line": 12, "source_lines": [12],
                "range_text": "3.9-6.1",
                "verification_reason": "同一 OCR 行识别到结果值及参考范围",
                "parser_version": "2.2.0",
            }
        ]],
    )
    created_at: datetime | None = None
    disclaimer: str = HEALTH_DISCLAIMER

    class Config:
        from_attributes = True


# ---------- 天气提醒 ----------

class WeatherRemind(BaseModel):
    city: str
    text: str = Field(..., description="天气概况，如 多云 18~26℃")
    tip: str = Field(..., description="给老人的弹窗提醒文案")
    warning: str | None = Field(None, description="预警信息，无则为空")

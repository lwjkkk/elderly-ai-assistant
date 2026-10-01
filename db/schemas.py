# Pydantic 校验模型：负责校验请求体长什么样、返回体长什么样
# 注意和 models.py 的区别：models 对应数据库表，schemas 对应接口的输入输出

from pydantic import BaseModel, Field


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


class LoginRequest(BaseModel):
    """登录请求体"""
    phone: str = Field(..., pattern=PHONE_PATTERN, description="11位手机号")
    password: str


class Token(BaseModel):
    """登录成功返回的令牌"""
    access_token: str
    token_type: str = "bearer"
    role: str
    nickname: str


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
    elder_id: int | None = Field(None, description="家属代录时指定老人id；老人自己录可不填")


class MedicationUpdate(BaseModel):
    """修改药品请求体（所有字段可选，只改传的）"""
    name: str | None = None
    dosage: str | None = None
    frequency: str | None = None
    times: list[str] | None = None


class MedicationOut(BaseModel):
    id: int
    elder_id: int
    created_by: int
    name: str
    dosage: str
    frequency: str
    times: list[str]

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
    value: str | None = Field(None, description="通用数值：血糖/心率/体重")
    elder_id: int | None = Field(None, description="家属代录时指定老人id")


class VitalsOut(BaseModel):
    id: int
    elder_id: int
    type: str
    systolic: int | None = None
    diastolic: int | None = None
    value: str | None = None
    measured_at: str | None = None

    class Config:
        from_attributes = True


class TrendPoint(BaseModel):
    """趋势图单个数据点"""
    date: str
    systolic: int | None = None
    diastolic: int | None = None
    value: str | None = None


# ---------- 问诊录音 ----------

class ConsultOut(BaseModel):
    id: int
    elder_id: int
    audio_url: str
    duration: int | None = None
    hospital: str | None = None
    doctor: str | None = None
    created_at: str | None = None

    class Config:
        from_attributes = True

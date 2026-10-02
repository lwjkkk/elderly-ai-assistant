# 银龄数字生活辅助智能体 — API 接口文档

> 版本：v2.0（基于 backend 分支实际代码生成）  
> 维护人：C（文档素材）  
> 更新时间：2026-10-02  
> 代码来源：`origin/backend` 分支  
> 对接方：A（后端 FastAPI）、B（前端 Flutter）

---

## 一、基础信息

| 项目 | 值 |
|---|---|
| 基础 URL（开发） | `http://127.0.0.1:8000` |
| 数据格式 | `application/json; charset=utf-8` |
| 文件上传 | `multipart/form-data` |
| 时间格式 | ISO 8601（如 `2026-10-02T14:30:00`） |
| 自动文档 | 启动后端后访问 `http://127.0.0.1:8000/docs`（Swagger UI） |

---

## 二、认证方式

### 2.1 JWT Token

- 登录成功返回 `access_token`，前端存入 `SharedPreferences`。
- 所有需鉴权接口在 HTTP Header 携带：

```
Authorization: Bearer <access_token>
```

### 2.2 角色

| role 值 | 含义 | 权限 |
|---|---|---|
| `elder` | 老人 | 操作自己的数据，调用时不传 `elder_id` |
| `family` | 家属 | 操作已绑定（status=active）老人的数据，调用时必须传 `elder_id` |

### 2.3 权限校验规则（A 已实现）

- 老人调用接口时，`elder_id` 自动取当前用户 ID，传了也会被忽略。
- 家属调用接口时，`elder_id` **必填**，且必须与该家属有 `active` 绑定关系，否则返回 403。

---

## 三、统一响应格式

### 3.1 成功响应

成功时 **直接返回数据对象**（不包裹 `code/message/data`），HTTP 状态码 200（创建为 201）。

### 3.2 错误响应

错误时返回：

```json
{
  "detail": "错误描述信息"
}
```

### 3.3 常见 HTTP 状态码

| 状态码 | 含义 | 典型场景 |
|---|---|---|
| 200 | 成功 | 查询、修改、删除 |
| 201 | 创建成功 | 注册、新增记录 |
| 400 | 参数错误 | 缺少必填字段、类型不对、邀请码过期 |
| 401 | 未认证 | 未带 Token、Token 无效 |
| 403 | 无权限 | 家属未绑定该老人、老人调用家属专属接口 |
| 404 | 资源不存在 | 药品/记录不存在、邀请码无效 |
| 422 | 请求体验证失败 | Pydantic 校验不通过（如手机号格式错误） |

---

## 四、免责声明

所有医疗相关接口响应中包含 `disclaimer` 字段。固定文案：

```
本内容仅供健康科普参考，不构成医疗诊断或用药建议。具体诊疗请遵医嘱，如有急症请立即拨打120。
```

涉及接口：`/api/drugs/*`、`/api/reports/*`、`/api/vitals/export`、`/api/symptom-check`。

---

## 五、接口详细说明

---

### 5.1 鉴权接口 `/api/auth`

#### 5.1.1 注册

- **接口**：`POST /api/auth/register`
- **鉴权**：不需要
- **HTTP 状态码**：201

**请求体：**

| 字段 | 类型 | 必填 | 说明 | 示例 |
|---|---|---|---|---|
| phone | string | 是 | 11位手机号，正则 `^1[3-9]\d{9}$` | `"13800138000"` |
| password | string | 是 | 密码，最少6位 | `"123456"` |
| nickname | string | 是 | 昵称 | `"张爷爷"` |
| role | string | 是 | `elder` 或 `family` | `"elder"` |

```json
{
  "phone": "13800138000",
  "password": "123456",
  "nickname": "张爷爷",
  "role": "elder"
}
```

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| id | integer | 用户ID |
| phone | string | 手机号 |
| nickname | string | 昵称 |
| role | string | 角色 |

```json
{
  "id": 1,
  "phone": "13800138000",
  "nickname": "张爷爷",
  "role": "elder"
}
```

**错误：**
- 400：角色不是 elder/family / 手机号已注册
- 422：手机号格式不对 / 密码少于6位

---

#### 5.1.2 登录

- **接口**：`POST /api/auth/login`
- **鉴权**：不需要

**请求体：**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| phone | string | 是 | 11位手机号 |
| password | string | 是 | 密码 |

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| access_token | string | JWT Token |
| token_type | string | 固定 `"bearer"` |
| role | string | 用户角色 |
| nickname | string | 用户昵称 |

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer",
  "role": "elder",
  "nickname": "张爷爷"
}
```

> **B 注意**：登录响应里没有单独的 `user` 对象，`role` 和 `nickname` 直接在顶层。保存 Token 时同时存 role。

**错误：**
- 401：手机号或密码错误

---

#### 5.1.3 刷新 Token

- **接口**：`POST /api/auth/refresh`
- **鉴权**：需要
- **用途**：延长 Token 有效期

**请求体：** 无（从 Header 解析当前用户）

**成功响应：** 同登录响应格式。

---

### 5.2 绑定接口 `/api/bind`

#### 5.2.1 生成邀请码

- **接口**：`POST /api/bind/invite`
- **鉴权**：需要（仅 `elder` 角色）
- **用途**：老人生成6位邀请码，30分钟有效

**请求体：** 无

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| invite_code | string | 6位邀请码（大写字母+数字） |

```json
{
  "invite_code": "A3B9X2"
}
```

> **业务规则**：每个老人同一时间只有一个有效邀请码，重新生成会覆盖旧的 pending 记录。

**错误：**
- 403：家属角色调用此接口

---

#### 5.2.2 接受绑定

- **接口**：`POST /api/bind/accept`
- **鉴权**：需要（仅 `family` 角色）

**请求体：**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| invite_code | string | 是 | 6位邀请码 |

```json
{
  "invite_code": "A3B9X2"
}
```

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| id | integer | 绑定记录ID |
| elder_id | integer | 老人ID |
| family_id | integer | 家属ID |
| status | string | 固定 `"active"` |
| invite_code | string | 邀请码 |

```json
{
  "id": 1,
  "elder_id": 1,
  "family_id": 2,
  "status": "active",
  "invite_code": "A3B9X2"
}
```

**错误：**
- 400：邀请码已过期（30分钟）
- 403：老人角色调用
- 404：邀请码无效或已被使用

---

#### 5.2.3 绑定列表

- **接口**：`GET /api/bind/list`
- **鉴权**：需要
- **用途**：老人看绑定的家属，家属看绑定的老人

**请求参数：** 无

**成功响应：** 返回数组

| 字段 | 类型 | 说明 |
|---|---|---|
| id | integer | 绑定记录ID |
| elder_id | integer | 老人ID |
| family_id | integer/null | 家属ID（pending 状态时为 null） |
| status | string | `pending` / `active` / `unbound` / `expired` |
| invite_code | string | 邀请码 |
| other_nickname | string/null | 对方昵称（前端直接展示用） |

```json
[
  {
    "id": 1,
    "elder_id": 1,
    "family_id": 2,
    "status": "active",
    "invite_code": "A3B9X2",
    "other_nickname": "小明"
  }
]
```

---

### 5.3 用药管理接口 `/api/meds`

#### 5.3.1 新增药品

- **接口**：`POST /api/meds`
- **鉴权**：需要

**请求体：**

| 字段 | 类型 | 必填 | 说明 | 示例 |
|---|---|---|---|---|
| name | string | 是 | 药品名 | `"硝苯地平缓释片"` |
| dosage | string | 是 | 剂量，如 `"1片"` / `"100mg"` | `"20mg"` |
| frequency | string | 是 | 频次，如 `"每日1次"` / `"每日3次"` | `"每日2次"` |
| times | array[string] | 是 | 服药时间点，格式 `HH:MM`，至少1个 | `["08:00","20:00"]` |
| elder_id | integer | 家属必填 | 家属代录时指定老人ID；老人自己录不传 | `1` |

```json
{
  "name": "硝苯地平缓释片",
  "dosage": "20mg",
  "frequency": "每日2次",
  "times": ["08:00", "20:00"]
}
```

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| id | integer | 药品ID |
| elder_id | integer | 老人ID |
| created_by | integer | 创建人ID |
| name | string | 药品名 |
| dosage | string | 剂量 |
| frequency | string | 频次 |
| times | array[string] | 服药时间点 |

**错误：**
- 400：times 为空 / 家属未传 elder_id
- 403：未绑定该老人

---

#### 5.3.2 药品列表

- **接口**：`GET /api/meds`
- **鉴权**：需要

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| elder_id | integer | 家属必填 | 老人ID |

**成功响应：** 返回药品数组（格式同新增响应）。

---

#### 5.3.3 修改药品

- **接口**：`PUT /api/meds/{med_id}`
- **鉴权**：需要

**路径参数：** `med_id` — 药品ID

**请求体：** 所有字段可选（只传要改的）

| 字段 | 类型 | 说明 |
|---|---|---|
| name | string | 药品名 |
| dosage | string | 剂量 |
| frequency | string | 频次 |
| times | array[string] | 服药时间点（至少1个） |

**成功响应：** 返回修改后的完整药品记录。

**错误：**
- 400：times 为空
- 403：无权限
- 404：药品不存在

---

#### 5.3.4 删除药品

- **接口**：`DELETE /api/meds/{med_id}`
- **鉴权**：需要
- **注意**：物理删除，同时删除该药品的所有打卡记录

**成功响应：**

```json
{
  "detail": "已删除"
}
```

---

#### 5.3.5 今日用药清单

- **接口**：`GET /api/meds/today`
- **鉴权**：需要
- **用途**：返回每个药品的所有时间点及打卡状态，前端直接渲染今日服药页

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| elder_id | integer | 家属必填 | 老人ID |
| date | string | 否 | 日期 `YYYY-MM-DD`，默认今天 |

**成功响应：** 返回数组

| 字段 | 类型 | 说明 |
|---|---|---|
| medication_id | integer | 药品ID |
| name | string | 药品名 |
| dosage | string | 剂量 |
| slots | array | 时间点及状态列表 |
| slots[].slot | string | 时间点，如 `"08:00"` |
| slots[].status | string | `pending`（未打卡）/ `taken`（已服）/ `missed`（漏服） |

```json
[
  {
    "medication_id": 1,
    "name": "硝苯地平缓释片",
    "dosage": "20mg",
    "slots": [
      {"slot": "08:00", "status": "taken"},
      {"slot": "20:00", "status": "pending"}
    ]
  }
]
```

---

#### 5.3.6 服药打卡

- **接口**：`POST /api/meds/checkin`
- **鉴权**：需要
- **用途**：标记某个时间点已服药（重复调用会覆盖为 taken）

**请求体：**

| 字段 | 类型 | 必填 | 说明 | 示例 |
|---|---|---|---|---|
| medication_id | integer | 是 | 药品ID | `1` |
| slot | string | 是 | 时间点，格式 `HH:MM` | `"08:00"` |
| date | string | 否 | 日期 `YYYY-MM-DD`，默认今天 | `"2026-10-02"` |

```json
{
  "medication_id": 1,
  "slot": "08:00"
}
```

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| id | integer | 打卡记录ID |
| medication_id | integer | 药品ID |
| elder_id | integer | 老人ID |
| date | string | 日期 |
| slot | string | 时间点 |
| status | string | 固定 `"taken"` |

**错误：**
- 404：药品不存在

---

### 5.4 查药接口 `/api/drugs`

#### 5.4.1 拍照查药

- **接口**：`POST /api/drugs/query`
- **鉴权**：需要
- **用途**：上传药盒照片 base64，OCR 识别 + AI 大白话解读

**请求体：**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| image_base64 | string | 是 | 药盒照片 base64（不含 `data:image/...;base64,` 前缀） |

```json
{
  "image_base64": "iVBORw0KGgoAAAANSUhEUg..."
}
```

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| ocr_text | string | OCR 识别出的药盒文字 |
| explanation | string | AI 大白话解读（作用/禁忌/副作用三部分） |
| disclaimer | string | 免责声明 |

```json
{
  "ocr_text": "硝苯地平缓释片 20mg 口服 每日一次",
  "explanation": "这个药主要用来降血压、缓解心绞痛。注意：服药期间不要突然停药，低血压的人要小心，可能会出现脸红、头痛、腿肿等不适。具体怎么吃请听医生的。",
  "disclaimer": "本内容仅供健康科普参考，不构成医疗诊断或用药建议。具体诊疗请遵医嘱，如有急症请立即拨打120。"
}
```

---

#### 5.4.2 按药名查药

- **接口**：`POST /api/drugs/query-name`
- **鉴权**：需要

**请求体：**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| name | string | 是 | 药品名 |

```json
{
  "name": "阿司匹林"
}
```

**成功响应：** 同拍照查药（`ocr_text` 为 `"药品名：阿司匹林"`）。

---

### 5.5 体征接口 `/api/vitals`

#### 5.5.1 录入体征

- **接口**：`POST /api/vitals`
- **鉴权**：需要

**请求体：**

| 字段 | 类型 | 必填 | 说明 | 示例 |
|---|---|---|---|---|
| type | string | 是 | 体征类型：`bp`（血压）/ `bs`（血糖）/ `hr`（心率）/ `weight`（体重） | `"bp"` |
| systolic | integer | 血压时必填 | 收缩压（高压），单位 mmHg | `145` |
| diastolic | integer | 血压时必填 | 舒张压（低压），单位 mmHg | `90` |
| value | float | 非血压时必填 | 血糖(mmol/L) / 心率(次/分) / 体重(kg) | `6.8` |
| elder_id | integer | 家属必填 | 老人ID | `1` |

**血压示例：**
```json
{
  "type": "bp",
  "systolic": 145,
  "diastolic": 90
}
```

**血糖示例：**
```json
{
  "type": "bs",
  "value": 6.8
}
```

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| id | integer | 记录ID |
| elder_id | integer | 老人ID |
| type | string | 体征类型 |
| systolic | integer/null | 收缩压 |
| diastolic | integer/null | 舒张压 |
| value | float/null | 数值 |
| measured_at | string | 测量时间（默认当前时间） |

**错误：**
- 400：type 不是 bp/bs/hr/weight / 血压缺少收缩压或舒张压 / 家属未传 elder_id
- 403：未绑定该老人

---

#### 5.5.2 体征列表

- **接口**：`GET /api/vitals`
- **鉴权**：需要

**查询参数：**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| vital_type | string | 否 | 全部 | 筛选类型：`bp`/`bs`/`hr`/`weight` |
| elder_id | integer | 家属必填 | - | 老人ID |
| days | integer | 否 | 30 | 最近天数 |

**成功响应：** 返回体征记录数组（格式同录入响应），按时间倒序。

---

#### 5.5.3 趋势数据

- **接口**：`GET /api/vitals/trend`
- **鉴权**：需要
- **用途**：按天聚合，前端 fl_chart 直接画曲线图

**查询参数：**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| vital_type | string | 否 | 全部 | 筛选类型 |
| elder_id | integer | 家属必填 | - | 老人ID |
| days | integer | 否 | 30 | 最近天数 |

**成功响应：** 返回对象，key 为体征类型，value 为数据点数组

```json
{
  "bp": [
    {"date": "2026-09-28", "systolic": 142, "diastolic": 88, "value": null},
    {"date": "2026-09-29", "systolic": 145, "diastolic": 90, "value": null}
  ],
  "bs": [
    {"date": "2026-09-28", "systolic": null, "diastolic": null, "value": 6.5},
    {"date": "2026-09-29", "systolic": null, "diastolic": null, "value": 6.8}
  ]
}
```

> **说明**：同一天有多条记录时取平均值。血压有 systolic/diastolic 两个值，其他类型只有 value。

---

#### 5.5.4 导出 PDF

- **接口**：`GET /api/vitals/export`
- **鉴权**：需要
- **返回**：PDF 文件流（`application/pdf`）

**查询参数：**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| vital_type | string | 否 | 全部 | 筛选类型 |
| elder_id | integer | 家属必填 | - | 老人ID |
| days | integer | 否 | 30 | 最近天数 |

**PDF 内容**：老人昵称、趋势图、数据表格、免责声明。

---

### 5.6 问诊录音接口 `/api/consults`

#### 5.6.1 上传录音

- **接口**：`POST /api/consults/upload`
- **鉴权**：需要
- **Content-Type**：`multipart/form-data`

**表单字段：**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| file | file | 是 | 录音文件，支持 mp3/wav/m4a/aac |
| duration | integer | 否 | 录音时长（秒） |
| hospital | string | 否 | 医院名 |
| doctor | string | 否 | 医生名 |
| elder_id | integer | 家属必填 | 老人ID |

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| id | integer | 记录ID |
| elder_id | integer | 老人ID |
| audio_url | string | 录音访问路径（如 `/api/consults/audio/xxx.mp3`） |
| duration | integer/null | 时长（秒） |
| hospital | string/null | 医院名 |
| doctor | string/null | 医生名 |
| created_at | string | 上传时间 |

**错误：**
- 400：不支持的音频格式

---

#### 5.6.2 问诊列表

- **接口**：`GET /api/consults`
- **鉴权**：需要

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| elder_id | integer | 家属必填 | 老人ID |

**成功响应：** 返回问诊记录数组，按时间倒序。

---

#### 5.6.3 播放录音

- **接口**：`GET /api/consults/audio/{filename}`
- **鉴权**：不需要
- **返回**：音频文件流

> 前端拼接 `http://host:port` + `audio_url` 即可播放。

---

### 5.7 症状自查接口 `/api/symptom-check`

#### 5.7.1 提交症状

- **接口**：`POST /api/symptom-check`
- **鉴权**：需要

**请求体：**

| 字段 | 类型 | 必填 | 说明 | 示例 |
|---|---|---|---|---|
| input_text | string | 是 | 症状描述 | `"最近总是头晕，早上起来尤其明显"` |
| elder_id | integer | 家属必填 | 老人ID | `1` |

```json
{
  "input_text": "最近总是头晕，早上起来尤其明显"
}
```

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| id | integer | 记录ID |
| elder_id | integer | 老人ID |
| input_text | string | 症状描述 |
| advice_text | string | AI 建议 |
| risk | string | 风险等级：`green` / `yellow` / `red` |
| created_at | string | 记录时间 |

```json
{
  "id": 1,
  "elder_id": 1,
  "input_text": "最近总是头晕，早上起来尤其明显",
  "advice_text": "您的症状可能与血压波动有关，建议先测量血压。如果头晕加重或出现肢体麻木、说话不清，请立即拨打120。",
  "risk": "yellow",
  "created_at": "2026-10-02T16:00:00"
}
```

**前端展示建议：**
- `red`：红色背景 + 大字警告 + "立即拨打120"
- `yellow`：黄色背景 + "建议尽快就医"
- `green`：绿色背景 + 日常护理建议

**错误：**
- 400：症状描述为空

---

#### 5.7.2 自查历史

- **接口**：`GET /api/symptom-check`
- **鉴权**：需要

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| elder_id | integer | 家属必填 | 老人ID |

**成功响应：** 返回自查记录数组，按时间倒序。

---

### 5.8 体检报告接口 `/api/reports`

#### 5.8.1 上传体检报告

- **接口**：`POST /api/reports/upload`
- **鉴权**：需要
- **Content-Type**：`multipart/form-data`

**表单字段：**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| file | file | 是 | 体检单图片，支持 jpg/png/webp |
| elder_id | integer | 家属必填 | 老人ID |

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| id | integer | 报告ID |
| elder_id | integer | 老人ID |
| image_url | string | 图片访问路径（如 `/api/reports/image/xxx.jpg`） |
| ocr_text | string | OCR 识别出的报告文字 |
| advice_text | string | AI 大白话建议（代码先精确判定指标，再 LLM 表达） |
| created_at | string | 上传时间 |

**错误：**
- 400：图片格式不支持

---

#### 5.8.2 报告列表

- **接口**：`GET /api/reports`
- **鉴权**：需要

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| elder_id | integer | 家属必填 | 老人ID |

**成功响应：** 返回报告记录数组，按时间倒序。

---

#### 5.8.3 查看原图

- **接口**：`GET /api/reports/image/{filename}`
- **鉴权**：不需要
- **返回**：图片文件流

---

### 5.9 天气提醒接口 `/api/weather`

#### 5.9.1 获取天气提醒

- **接口**：`GET /api/weather/remind`
- **鉴权**：需要

**查询参数：**

| 参数 | 类型 | 必填 | 说明 | 示例 |
|---|---|---|---|---|
| city | string | 否 | 城市名（不传则用定位或默认） | `"武汉"` |
| lat | float | 否 | 纬度（App 定位后传入，精确到区县） | `30.5928` |
| lon | float | 否 | 经度 | `114.3055` |

> 优先用 lat/lon 精确定位；不传则用 city；都不传用后端默认位置。

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| city | string | 城市名 |
| text | string | 天气概况，如 `"多云 18~26℃"` |
| tip | string | 给老人的弹窗提醒文案 |
| warning | string/null | 预警信息，无则为 null |

```json
{
  "city": "武汉",
  "text": "小雨 16~20℃",
  "tip": "今天降温下雨，出门记得带伞、加件外套，路滑小心摔倒。",
  "warning": null
}
```

---

### 5.10 智能问答接口 `/api/chat`

#### 5.10.1 办事助手问答

- **接口**：`POST /api/chat`
- **鉴权**：不需要
- **用途**：老人端办事助手，文字问答（截图功能已从日常问答下线，体检查药 OCR 走专用接口）

**请求体：**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| question | string | 是 | 用户问题文字 |

```json
{
  "question": "微信怎么发语音"
}
```

**成功响应：**

| 字段 | 类型 | 说明 |
|---|---|---|
| answer | string | 完整回答 |
| module | string | 命中模块：`phone` / `services` / `daily_life` |
| steps | array | 操作步骤数组 |
| disclaimer | string | 免责声明 |

---

## 六、接口汇总表

| 模块 | 方法 | 路径 | 鉴权 | 对应计划日 |
|---|---|---|---|---|
| 鉴权 | POST | `/api/auth/register` | 否 | Day1 |
| 鉴权 | POST | `/api/auth/login` | 否 | Day1 |
| 鉴权 | POST | `/api/auth/refresh` | 是 | Day1 |
| 绑定 | POST | `/api/bind/invite` | 是(老人) | Day1 |
| 绑定 | POST | `/api/bind/accept` | 是(家属) | Day1 |
| 绑定 | GET | `/api/bind/list` | 是 | Day1 |
| 用药 | POST | `/api/meds` | 是 | Day2 |
| 用药 | GET | `/api/meds` | 是 | Day2 |
| 用药 | PUT | `/api/meds/{med_id}` | 是 | Day2 |
| 用药 | DELETE | `/api/meds/{med_id}` | 是 | Day2 |
| 用药 | GET | `/api/meds/today` | 是 | Day2 |
| 用药 | POST | `/api/meds/checkin` | 是 | Day2 |
| 查药 | POST | `/api/drugs/query` | 是 | Day2 |
| 查药 | POST | `/api/drugs/query-name` | 是 | Day2 |
| 体征 | POST | `/api/vitals` | 是 | Day3 |
| 体征 | GET | `/api/vitals` | 是 | Day3 |
| 体征 | GET | `/api/vitals/trend` | 是 | Day3 |
| 体征 | GET | `/api/vitals/export` | 是 | Day3 |
| 问诊 | POST | `/api/consults/upload` | 是 | Day3 |
| 问诊 | GET | `/api/consults` | 是 | Day3 |
| 问诊 | GET | `/api/consults/audio/{filename}` | 否 | Day3 |
| 症状 | POST | `/api/symptom-check` | 是 | Day4 |
| 症状 | GET | `/api/symptom-check` | 是 | Day4 |
| 报告 | POST | `/api/reports/upload` | 是 | Day4 |
| 报告 | GET | `/api/reports` | 是 | Day4 |
| 报告 | GET | `/api/reports/image/{filename}` | 否 | Day4 |
| 天气 | GET | `/api/weather/remind` | 是 | Day4 |
| 问答 | POST | `/api/chat` | 否 | Day5 |

---

## 七、前端对接注意事项（给 B）

1. **登录响应**：`role` 和 `nickname` 在响应顶层，不在 `user` 对象里。保存 Token 时同时存 role。
2. **老人ID**：老人端所有接口不传 `elder_id`；家属端必须传。
3. **体征类型**：用 `bp`/`bs`/`hr`/`weight`，不是 `blood_pressure` 等长名。
4. **打卡接口**：是 `POST /api/meds/checkin`，请求体带 `medication_id` 和 `slot`，不是路径参数。
5. **今日清单**：`GET /api/meds/today` 返回的 slots 里 status 有 `pending`（未打卡），前端用这个判断哪些还没吃。
6. **文件上传**：录音和体检报告用 `multipart/form-data`，不是 JSON。
7. **图片/音频访问**：后端返回的 `image_url`/`audio_url` 是相对路径（如 `/api/reports/image/xxx.jpg`），前端拼接 `baseUrl` 使用。
8. **401 处理**：收到 401 清除本地 Token 跳转登录页。
9. **枚举值**：所有 status/type/risk 用英文值判断，不要硬编码中文。
10. **趋势图**：`/api/vitals/trend` 返回的是对象（key 为类型），不是数组；血压有 systolic/diastolic 两个值。

---

## 八、变更记录

| 版本 | 日期 | 修改人 | 修改内容 |
|---|---|---|---|
| v1.0 | 2026-10-02 | C | 初始版本（基于计划文档推测） |
| v2.0 | 2026-10-02 | C | 基于 backend 分支实际代码重写，修正所有接口路径、参数、响应格式 |

---

> **本文档与 A 的 backend 分支代码保持一致。如有接口调整，请 A 修改代码后通知 C 更新文档，确保前后端对齐。**

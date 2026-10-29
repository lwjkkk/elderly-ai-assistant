# 基于 RAG 的适老化健康与数字生活智能体

> 团队：云栖码梦 | 参赛编号：AIC-2026-44306158
> 本仓库包含后端 FastAPI 与 Flutter 前端双端源码。

面向老年人的 AI 健康助手与数字生活辅助 App。支持用药提醒与打卡、体征记录、体检报告 OCR 识别与解读、AI 问事（老人简版/家属详版）、急症双级预警、语音转写、家属端协同。

## 评审与部署入口

- [安装部署与使用说明](安装部署与使用说明.md)：后端环境、依赖、`.env` 配置、模型下载、本地启动、Linux/systemd + Nginx 部署、故障排查。
- [评审使用说明](评审使用说明.md)：评委两种体验方式（装正式 APK 直接体验 / 从源码复现）、演示账号交接、建议体验顺序与权限边界。
- 已部署体验地址：`http://47.93.97.48:8000`（当前为 HTTP，未配置 HTTPS；正式 APK 已写入该地址，旧包不会自动切换）。
- 演示账号与口令通过参赛平台允许的受限方式单独提供，不写在公开仓库或本 README 中。

---

## 一、核心功能

### 1.1 健康管理

| 功能 | 说明 |
|---|---|
| 💊 用药管理 | 录入药品、设置服药时间，前端本地定时通知提醒，到点后 60 分钟内可打卡，家属端可查看记录 |
| 📊 体征记录 | 血压、血糖、心率、体重录入，趋势曲线图，PDF 导出 |
| 📄 体检报告 | 上传体检单照片，PaddleOCR 结构化识别 + AI 适老解读（仅健康科普，不做诊断） |
| ⚠️ 急症预警 | 本地规则快速命中 + Qwen 限时语义筛查兜底，红色紧急提醒 + 120 引导 + 有权限家属的应用内消息 |
| 🎙️ 语音转写 | 录音上传后端 ASR 转写，用户确认后再提交健康记录，不依赖手机系统语音识别 |

> 通知边界：家属端收到的是**应用内消息**，用药到点是**前端本地定时通知**；当前未接入系统级远程推送通道，不保证所有后台场景均弹窗响铃。

### 1.2 数字生活辅助

| 功能 | 说明 |
|---|---|
| 📱 手机操作教程 | 微信、支付宝、手机设置等操作步骤详解 |
| 🏥 便民办事科普 | 医保挂号、社保查询、火车票购买、证件办理等流程指引 |
| 📚 生活常识问答 | 健康饮食、居家安全、防诈骗、防跌倒等科普 |
| 🔍 AI 问事 | 文字输入提问，老人简版大字回答 + 家属详版详细回答，底部附知识库来源卡片 |

### 1.3 双角色体系

| 角色 | Tab |
|---|---|
| 👴 老人端 | 用药提醒、AI 问事、家人互动、个人中心 |
| 👨‍👩‍👧 家属端 | 健康总览、AI 问事、家人互动、个人中心 |

家属通过邀请码绑定老人后，可在授权范围内查看健康数据与接收异常事件同步；满 60 周岁对有效绑定家属按既定范围共享，未满 60 周岁按分享设置，出生年月未知时限制家属访问。

---

## 二、技术栈

### 2.1 后端

| 技术 | 版本 | 用途 |
|---|---|---|
| Python | **3.13**（本机验证 3.13.5 / Ubuntu 22.04 验证 3.13.18） | 开发语言 |
| FastAPI | 0.143+ | Web 框架，自动生成 API 文档（`/docs`） |
| SQLAlchemy | 2.1.5 | ORM，数据库建模（16 张业务表） |
| SQLite | 3 | 数据库（含建表、迁移与索引逻辑） |
| Pydantic | v2 | 请求/响应数据校验 |
| BGE-small-zh-v1.5 | — | 本地向量编码（MIT） |
| PaddleOCR | 3.7.0（PP-OCRv6 medium 检测与识别） | 体检报告文字识别（Apache-2.0） |
| Qwen3.7-plus / Qwen3.8-flash | — | 云端文本生成与急症语义筛查主备 |
| qwen3-asr-flash / qwen-audio-3.1-asr-flash | — | 云端语音转写主备 |
| APScheduler | 3.11 | 用药打卡时间窗口调度 |
| ReportLab | 5.0 | PDF 导出（体征报告） |
| bcrypt + JWT | — | 用户认证 |

- RAG 为**自研轻量检索与校验流程**：BGE 向量编码 + SQLite 向量存储 + 混合检索 + 来源卡片校验；**不依赖** Ollama、LangChain 或 ChromaDB。
- 文本与语音默认走阿里云百炼主备模型，仅在策略明确识别到额度耗尽时才切备用；网络故障、鉴权失败、模型无权限不会自动切换。

### 2.2 前端

Flutter 3 双端 App，源码位于 `app_flutter/`，入口 `app_flutter/lib/main.dart`，API 地址由 `lib/config.dart` 通过 `--dart-define=API_BASE=...` 注入。前端详细目录、构建与测试说明见 [app_flutter/README.md](app_flutter/README.md)（前端维护分支为 `front`）。

### 2.3 知识库

`knowledge_base/` 共 203 篇 TXT 文章，已部署版本建索引后为 340 个检索分块，其中 116 篇附官方来源，覆盖：健康科普、手机操作教程、便民办事流程、生活常识。

---

## 三、目录结构

```
elderly-ai-assistant/
├── api/                  # API 路由（16 个路由文件；具体接口以运行时 /docs 为准）
├── core/                 # 核心逻辑：RAG 检索链、急症预警、OCR 后处理、权限控制
├── db/                   # 数据库模型、初始化、迁移
├── services/             # 业务服务层
├── scripts/              # 运维脚本：初始化数据库、回归、手工入口等
├── tests/                # 测试：unit / integration / manual / fixtures
├── docs/                 # 文档：接口文档、设计规范、测试报告、开发日志
├── knowledge_base/       # 知识库原文（203 篇 TXT）
├── app_flutter/          # Flutter 前端完整代码
├── main.py               # 后端入口
├── requirements.txt      # Python 依赖
├── .env.example          # 空配置模板（真实密钥放 .env，不入库）
├── 安装部署与使用说明.md
├── 评审使用说明.md
└── README.md
```

---

## 四、快速开始

> 完整步骤、Linux/systemd + Nginx 部署与故障排查见 [安装部署与使用说明](安装部署与使用说明.md)。
> 本项目有两种运行方式，请按你的目的选一种，不要把它们混在一起。

### 方式 A：直接使用已部署云后端（评委体验、只跑 App 时选这个）

不需要安装 Python、不需要配置 `.env`、不需要下载模型。云后端已经在跑，前端只需要在构建时把后端地址指过去：

```powershell
cd app_flutter
flutter pub get
flutter build apk --release --dart-define=API_BASE=http://47.93.97.48:8000
```

- 云后端：`http://47.93.97.48:8000`（HTTP，未配置 HTTPS）。
- 百炼 / OCR / 向量模型等密钥由云后端保管，不写入前端，也不放进 APK。
- 仅体验正式 APK 无需任何密钥；费用与可用性由团队服务账号保障。

### 方式 B：从源码自行运行后端（复现、二次开发时选这个）

需要 Python 3.13、依赖、`.env` 密钥和首次模型下载：

```powershell
# 建议 Python 3.13 虚拟环境
py -3.13 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env   # 仅首次；已有 .env 不要覆盖
```

编辑 `.env`，至少填写：
- `DASHSCOPE_API_KEY`：百炼控制台生成、有对应模型权限的真实密钥；
- `SECRET_KEY`：本机生成的长随机串（`python -c "import secrets;print(secrets.token_urlsafe(48))"`）。

新建演示数据库（指向独立的新库，不要误指已有生产库）：

```powershell
.\.venv\Scripts\python.exe scripts\init_db.py --database ./elderly.db
```

首次启动会联网下载 BGE 与 PaddleOCR 权重并建立本地向量索引：

```powershell
.\.venv\Scripts\python.exe main.py
```

- 首页：`http://127.0.0.1:8000/`
- 交互接口文档：`http://127.0.0.1:8000/docs`

前端本地联调时，把 `API_BASE` 指到本机后端即可（详见 [app_flutter/README.md](app_flutter/README.md)）。

---

## 五、测试

测试版本：提交冻结版 v1.0（前端 `acbccb7` / 后端 `4c063e8`），测试日期 2026-10-28。

| 层级 | 结果 | 证据与口径 |
|---|---|---|
| 后端 pytest 单元回归 | 全部通过 | 日志 `docs/test-report/01_自动化回归测试/backend_pytest_output.txt`（云服务器环境：Ubuntu 22.04 + Python 3.13 + FFmpeg + fonts-wqy-zenhei）。<br>本地 Windows 开发机未安装 FFmpeg / 中文字体时，4 条音频解码用例与 1 条 PDF 导出用例会因缺解码器或字体标记失败，属本机环境差异，不是代码缺陷；云端已安装依赖后全部通过。 |
| 后端云服务器分层回归 | 按模块记录（综合业务、RAG 检索、OCR、用药、紧急、语音等），29 份原始日志 + 45 个证据摘录 | 含真实 PaddleOCR / BGE / Qwen / ASR 调用，按模块独立统计、不累计为单一总数；详见 [docs/test-report/](docs/test-report/00_测试总览.md) |
| 前端 Flutter 测试 | 88 项通过 | widget + 契约测试，日志 `flutter_test_output.txt` |
| 真机验收 | **79 个用例通过**（老人端 53 + 家属端 18 + 端到端 8） | 荣耀 200 Pro，Android 14 |

> 不再使用根目录已失效的 `verify_all.py`；本地隔离替身回归与真实云调用是两套口径，分别记录。

---

## 六、开源与许可证

团队自写源码采用 **MIT 许可证**（见 `LICENSE`）。第三方组件按其各自许可证适用，完整声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

边界说明：

- 后端直接依赖以 BSD / MIT / Apache-2.0 为主；关键间接依赖 `crc32c`（LGPL-2.1）、`certifi`/`tqdm`（MPL-2.0）须随发行包保留各自许可文本。
- FFmpeg 通过 `subprocess` 独立进程调用（GPL-3.0-or-later），本仓库源码树不含其二进制；如发行物打包该二进制，须单独遵守 GPL 并提供源码。
- 模型：BGE-small-zh-v1.5（MIT）、PaddleOCR/PaddlePaddle（Apache-2.0）；百炼 Qwen/ASR 为云服务调用，按其服务条款，MIT 不授权模型权重。
- 视觉素材（`assets_src/`、`touxiang/`、`app_flutter/assets/`）授权依据待补，不随仓库主张 MIT 再分发。
- `knowledge_base/` 203 篇为团队整理并附官方来源，外部引用条目（如 NHS）按原网站 OGL 条款署名，不整库按 MIT 再分发。
- 本仓库不包含模型权重、真实用户数据库、上传文件、API 密钥或服务器凭据。

---

## 七、使用边界

- 本产品用于健康科普与信息整理，**不能替代医生诊疗**，不根据聊天自行调整药物剂量；真实紧急情况请立即拨打 120。
- 演示数据均为人工合成，不使用真实个人健康信息。
- 知识库来源卡片仅证明相关参考资料，不等同于回答中每一项判断均已专业审核。

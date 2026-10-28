# 云栖码梦 — 银龄数字生活辅助智能体

> 分支分工：`main` 为稳定后端，`backend` 为后端开发，Flutter 前端维护在 [front 分支](https://github.com/lwjkkk/elderly-ai-assistant/tree/front)。知识库保留在后端的 `knowledge_base/`，原知识库分支已备份并删除。详见 [整理与恢复说明](docs/repository-cleanup-20261029.md)。

> 面向老年人的 AI 健康助手与数字生活辅助 App。支持用药提醒、体征记录、体检报告解读、症状自查、拍照查药、问诊录音、天气健康提醒，以及手机操作/便民办事/生活常识的智能问答。

---

## 一、项目简介

本项目面向老年人**智能设备操作困难**和**健康管理不便**两大数字困境，依托开源生态搭建适老化 AI 辅助智能体。

项目采用 **FastAPI 后端 + Flutter 双端 App** 架构，融合大语言模型（Qwen）、OCR（PaddleOCR）、向量检索（LangChain + ChromaDB）等开源技术，提供两大核心能力：

1. **健康管理**：用药提醒与打卡、体征记录与趋势分析、体检报告 AI 解读、症状自查风险分级、拍照查药科普、问诊录音存档、天气健康提醒
2. **数字生活辅助**：手机操作教程、便民办事流程科普、老年生活常识问答，支持文字/语音输入和语音播报

系统设置**老人端**和**家属端**双角色，家属绑定老人后可远程查看健康数据、代录信息、接收异常提醒。

---

## 二、核心功能

### 2.1 健康管理（老人端 + 家属端）

| 功能 | 说明 |
|---|---|
| 💊 用药管理 | 录入药品、设置服药时间、定时推送提醒、服药打卡、家属同步查看 |
| 📸 拍照查药 | 拍摄药盒照片，OCR 识别 + AI 大白话解读（作用/禁忌/副作用） |
| 📊 体征记录 | 血压、血糖、心率、体重录入，趋势曲线图，PDF 导出 |
| 📄 体检报告 | 上传体检单照片，OCR 识别 + AI 解读建议（仅科普，不做诊断） |
| ⚠️ 症状自查 | 输入症状，AI 风险分级（绿/黄/红）+ 建议，高风险引导就医 |
| 🎙️ 问诊录音 | 就诊录音上传存档，可回放，记录医院和医生信息 |
| 🌤️ 天气提醒 | 基于定位的天气 + 健康提醒（降温加衣、雾霾减少外出等） |

### 2.2 数字生活辅助（老人端）

| 功能 | 说明 |
|---|---|
| 📱 手机操作教程 | 微信、支付宝、手机设置等操作步骤详解 |
| 🏥 便民办事科普 | 医保挂号、社保查询、火车票购买、证件办理等流程指引 |
| 📚 生活常识问答 | 健康饮食、居家安全、防诈骗、防跌倒等科普 |
| 🎤 语音交互 | 语音输入（语音转文字）+ 语音播报（文字转语音），支持方言 |
| 🔍 截图解析 | 上传手机操作截图，AI 识别界面并讲解下一步（体检查药 OCR 专用） |

### 2.3 双角色体系

| 角色 | 功能 |
|---|---|
| 👴 老人端 | 5个Tab：首页、办事助手、健康管理、问诊记录、我的；大字体大按钮，全局语音悬浮球 |
| 👨‍👩‍👧 家属端 | 4个Tab：首页、老人健康、问诊记录、我的；绑定老人后可查看健康数据、代录信息、接收提醒 |

---

## 三、技术栈

### 3.1 后端

| 技术 | 版本 | 用途 |
|---|---|---|
| Python | 3.10+ | 开发语言 |
| FastAPI | 0.115+ | Web 框架，自动生成 API 文档 |
| SQLAlchemy | 2.0 | ORM，数据库建模 |
| SQLite | 3 | 开发环境数据库（可无缝切换 MySQL） |
| Pydantic | v2 | 请求/响应数据校验 |
| PaddleOCR | 2.9 | 图片文字识别（药盒、体检报告） |
| LangChain | 0.3 | RAG 框架 |
| ChromaDB | 0.5 | 向量数据库 |
| Qwen2 (Ollama) | 7B | 本地开源大语言模型（可切换云端通义千问 API） |
| APScheduler | - | 定时任务（用药提醒推送） |
| ReportLab | - | PDF 导出（体征报告） |
| bcrypt | - | 密码哈希 |
| JWT (PyJWT) | - | Token 认证 |

### 3.2 前端

Flutter 源码、依赖、资源和构建说明维护在 [front 分支](https://github.com/lwjkkk/elderly-ai-assistant/tree/front)。前端入口为该分支的 `app_flutter/lib/main.dart`；本分支只保留后端和共享资料。

### 3.3 知识库

- 四大分类，共 **96篇** 知识文章：
  - `phone_tutorial/`：手机操作教程 20篇
  - `services/`：便民办事流程 27篇
  - `daily_life/`：生活常识 24篇
  - `health/`：健康科普 25篇

---

## 四、目录结构

```
elderly-ai-assistant/
├── api/                          # API 路由（按模块拆分）
│   ├── auth.py                   # 鉴权：注册、登录、刷新Token
│   ├── bind.py                   # 家属绑定：生成邀请码、接受绑定、绑定列表
│   ├── meds.py                   # 用药管理：增删改查、今日清单、打卡
│   ├── drugs.py                  # 拍照查药、按药名查询
│   ├── vitals.py                 # 体征记录、趋势查询、PDF导出
│   ├── consults.py               # 问诊录音上传、列表、播放
│   ├── symptom.py                # 症状自查风险分级
│   ├── reports.py                # 体检报告上传、OCR识别、AI解读
│   ├── weather.py                # 天气健康提醒
│   └── routes.py                 # 原有智能问答 /api/chat
├── config/
│   └── settings.py               # 配置：模型地址、API Key、服务器端口
├── core/                         # 核心业务逻辑
│   ├── agent.py                  # 智能体主函数（RAG + LLM + 步骤解析）
│   ├── qwen_llm.py               # 通义千问/Qwen 模型调用封装
│   ├── rag.py                    # 知识库检索（关键词 + 中文分词）
│   ├── ocr.py                    # PaddleOCR 图片识别封装
│   ├── health_llm.py             # 健康类 AI 提示词与调用（症状自查、体检解读）
│   ├── report_parse.py           # 体检报告指标解析（精确判定正常/偏高/偏低）
│   ├── prompt.py                 # 适老化系统提示词
│   ├── disclaimer.py             # 统一免责声明常量
│   └── security.py               # 密码哈希、JWT 生成与校验
├── db/                           # 数据库
│   ├── database.py               # 数据库连接、会话、建表
│   ├── models.py                 # SQLAlchemy 表模型（8张表）
│   └── schemas.py                # Pydantic 请求/响应模型
├── docs/                         # 项目文档
│   ├── API接口文档.md             # 完整 API 接口定义
│   ├── 数据库设计与字段字典.md      # 8张表完整字段说明
│   ├── 免责声明与伦理合规文档.md    # 免责声明、隐私保护、违禁词清单
│   ├── 适老化设计规范.md           # 字体/颜色/按钮/语音/AI回答全方面规范
│   └── self_test_results.md      # 自测结果记录
├── knowledge_base/               # 知识库（96篇 txt）
│   ├── phone_tutorial/           # 手机操作教程 20篇
│   ├── services/                 # 便民办事流程 27篇
│   ├── daily_life/               # 生活常识 24篇
│   └── health/                   # 健康科普 25篇
├── services/                     # 后端服务
│   ├── push.py                   # 推送服务（JPush，预留接口）
│   ├── scheduler.py              # 定时任务（用药提醒、漏服标记）
│   ├── pdf_export.py             # PDF 生成（体征报告）
│   └── weather.py                # 天气 API 封装（和风天气）
├── utils/                        # 工具函数
├── uploads/                      # 上传文件（录音、体检报告图片，运行时自动创建）
├── main.py                       # 后端入口，启动 FastAPI 服务
├── web_app.py                    # [Legacy] Gradio Web 界面（已冻结，备查）
├── requirements.txt              # Python 依赖
├── postman_collection.json       # Postman 接口测试集合
├── test_agent.py                 # 智能体冒烟测试
├── test_chat.py                  # 问答接口测试
├── test_drug.py                  # 拍照查药测试
├── batch_test.py                 # 批量自测脚本
├── verify_all.py                 # 全模块一键回归测试
├── verify_day1.py                # Day1 验证（鉴权绑定）
├── verify_day2.py                # Day2 验证（用药查药）
├── verify_day4.py                # Day4 验证（自查报告天气）
├── verify_day5.py                # Day5 验证（问答迁移）
├── verify_validation.py          # 输入校验与违禁词扫描
└── README.md                     # 本文件
```

---

## 五、快速开始

### 5.1 环境要求

- Python 3.10+
- Flutter 3.x（前端开发需要，仅运行后端不需要）
- Ollama（本地模型，可选，可切换云端 API）

### 5.2 后端启动

```bash
# 1. 克隆项目
git clone https://github.com/lwjkkk/elderly-ai-assistant.git
cd elderly-ai-assistant

# 2. 安装依赖
pip install -r requirements.txt

# 3. 配置（可选）
# 复制 .env.example 为 .env，填写 DASHSCOPE_API_KEY（使用云端模型时）
# 默认使用本地 Ollama qwen2:7b，无需配置

# 4. 启动后端
python main.py
```

启动后访问：
- API 服务：`http://127.0.0.1:8000`
- 自动 API 文档（Swagger UI）：`http://127.0.0.1:8000/docs`
- 健康检查：`http://127.0.0.1:8000/`

### 5.3 模型配置

**本地模型（默认，免费离线）：**
```bash
# 安装 Ollama 后拉取模型
ollama pull qwen2:7b
```
`config/settings.py` 中 `LLM_BASE_URL = "http://localhost:11434/v1"`，`QWEN_MODEL_NAME = "qwen2:7b"`。

**云端 API（通义千问，效果更好）：**
在 `.env` 中设置 `DASHSCOPE_API_KEY`，并将 `config/settings.py` 中 `LLM_BASE_URL` 改为 `https://dashscope.aliyuncs.com/compatible-mode/v1`。

### 5.4 前端启动（front 分支）

前端已迁入独立的 `front` 分支，请在另一个目录检出，避免切换正在运行的后端工作区：

```bash
git clone --branch front --single-branch https://github.com/lwjkkk/elderly-ai-assistant.git elderly-ai-assistant-front
cd elderly-ai-assistant-front/app_flutter
flutter pub get
flutter run -d edge --dart-define=API_BASE=http://101.201.226.34:8000
```

完整运行和打包说明见 [front 分支前端 README](https://github.com/lwjkkk/elderly-ai-assistant/blob/front/app_flutter/README.md)。`API_BASE` 应填写实际后端地址；本分支不再存放 Flutter 源码和前端历史工具。

### 5.5 运行测试

```bash
# 全模块回归测试
python verify_all.py

# 按天验证
python verify_day1.py   # 鉴权绑定
python verify_day2.py   # 用药查药
python verify_day4.py   # 自查报告天气

# 智能体冒烟测试
python test_agent.py

# 批量自测
python batch_test.py
```

---

## 六、数据库设计

共 **8张表**：

| 表名 | 说明 |
|---|---|
| `users` | 用户表（老人/家属，role 区分） |
| `family_bindings` | 家属绑定关系表（邀请码机制） |
| `medications` | 用药计划表 |
| `medication_logs` | 服药打卡记录表 |
| `vitals` | 体征记录表（血压/血糖/心率/体重） |
| `consult_records` | 问诊录音记录表 |
| `health_reports` | 体检报告表 |
| `symptom_checks` | 症状自查记录表 |

详细字段设计见 [`docs/数据库设计与字段字典.md`](docs/数据库设计与字段字典.md)。

---

## 七、API 接口

共 **10个模块，28个接口**：

| 模块 | 接口数 | 说明 |
|---|---|---|
| 鉴权 `/api/auth` | 3 | 注册、登录、刷新Token |
| 绑定 `/api/bind` | 3 | 生成邀请码、接受绑定、绑定列表 |
| 用药 `/api/meds` | 6 | 增删改查、今日清单、打卡 |
| 查药 `/api/drugs` | 2 | 拍照查药、按药名查询 |
| 体征 `/api/vitals` | 4 | 录入、列表、趋势、PDF导出 |
| 问诊 `/api/consults` | 3 | 上传、列表、播放 |
| 症状自查 `/api/symptom-check` | 2 | 提交、历史 |
| 体检报告 `/api/reports` | 3 | 上传、列表、查看图片 |
| 天气 `/api/weather` | 1 | 天气健康提醒 |
| 问答 `/api/chat` | 1 | 智能问答 |

详细接口定义见 [`docs/API接口文档.md`](docs/API接口文档.md)。启动后端后也可访问 `http://127.0.0.1:8000/docs` 查看交互式文档。

---

## 八、免责声明

本产品涉及健康医疗的功能（用药提醒、体征记录、体检报告解读、症状自查、拍照查药）仅为**健康科普与信息整理**，**不能替代医生面诊，不构成疾病诊断或用药建议**。如有不适，请及时咨询医生或拨打急救电话。

详细合规说明见 [`docs/免责声明与伦理合规文档.md`](docs/免责声明与伦理合规文档.md)。

---

## 九、许可证

本项目为开源项目，采用 MIT 许可证。

---

> 云栖码梦团队 · 2026 国庆七天交付

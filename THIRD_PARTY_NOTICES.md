# 第三方组件与开源许可声明（THIRD-PARTY NOTICES）

本文件随源码仓库一起分发。团队自写源码采用 MIT 许可证（见根目录 LICENSE）；本文件列出的第三方组件按其各自许可证适用，**不**因在本仓库出现就被重新声明为团队所有的 MIT 代码。

核查日期：2026-10-29。本清单基于仓库快照、本机已安装依赖元数据与远程 Flutter 锁文件初筛，不是完整法律意见，也不是完整 SBOM。未逐包核验原生传递依赖、模型资产、构建工具链与云端部署环境。

---

## 1. 团队自写源码

- 许可：MIT（见根目录 `LICENSE`，Copyright (c) 2026 云栖码梦团队）。
- 范围：后端 `api/ core/ db/ services/ utils/ scripts/`、前端 `app_flutter/lib/` 中由团队编写的业务代码。
- 本仓库**不包含**：BGE/PaddleOCR 模型权重、真实用户数据库、上传的体检单、百炼/天气 API 密钥、SSH 私钥。

## 2. 后端直接运行依赖

以下为 `requirements.txt` 锁定的直接依赖；完整元数据见 `docs/backend_dependency_inventory.csv`。

| 组件 | 版本 | 许可证 | 说明 |
|---|---|---|---|
| FastAPI | 0.143.3 | MIT | Web 框架 |
| Uvicorn | 0.54.0 | BSD-3-Clause | ASGI 服务器 |
| Pydantic / pydantic-settings | 2.14.1 / 2.16.0 | MIT | 数据校验 |
| SQLAlchemy | 2.1.5 | MIT | ORM |
| python-multipart | 0.0.32 | Apache-2.0 | multipart 表单解析 |
| OpenAI Python SDK | 3.35.1 | Apache-2.0 | 百炼 OpenAI 兼容客户端 |
| httpx | 0.28.1 | BSD-3-Clause | HTTP 客户端 |
| python-dotenv | 1.2.4 | BSD-3-Clause | .env 加载 |
| PyJWT / bcrypt | 2.15.1 / 5.0.0 | MIT / Apache-2.0 | 认证 |
| APScheduler | 3.11.3 | MIT | 用药打卡调度 |
| ReportLab | 5.0.1 | BSD-3-Clause | PDF 导出 |
| jieba | 0.42.1 | MIT | 中文分词 |
| NumPy | 2.3.1 | BSD-3-Clause（wheel 内附带第三方许可声明，须随发行包完整保留） | 数值计算 |
| Pillow | 11.3.0 | MIT-CMU | 图像处理 |
| Matplotlib | 3.10.3 | Matplotlib 自有许可（见随包 LICENSE） | 趋势图 |
| Transformers | 5.20.1 | Apache-2.0 | BGE 加载 |
| sentence-transformers | 6.1.0 | Apache-2.0 | 向量编码 |
| PyTorch | 2.14.1 | Apache-2.0 / LLVM-exception / BSD-2-Clause / BSD-3-Clause / BSL-1.0 / MIT 组合 | CPU 推理 |
| PaddleOCR / PaddlePaddle | 3.7.0 / 3.3.1 | Apache-2.0 | OCR（PP-OCRv6 medium） |
| OpenCV Python | 5.0.0.93 | Apache-2.0 | 图像预处理 |
| protobuf | 7.36.2 | BSD-3-Clause | PaddleX 依赖 |
| imageio-ffmpeg | 0.6.0 | BSD-2-Clause（Python 包装层） | 见第 4 节 FFmpeg 特别说明 |

Apache-2.0 组件再分发时，须保留其 LICENSE 副本、NOTICE（如有）与修改说明；不能只列包名。

## 3. 关键间接依赖（非直接列出，但随发行包分发）

| 组件 | 版本 | 许可证 | 处理要求 |
|---|---|---|---|
| crc32c | 2.9.post0 | LGPL-2.1-or-later（含 BSD 第三方声明） | 随运行包分发时保留 LGPL 文本与版权声明，提供库替换/重新链接所需信息，不将其改标 MIT |
| certifi | 2026.7.22 | MPL-2.0 | 保留 MPL 声明并提供源码获取方式 |
| tqdm | 4.70.1 | MPL-2.0 AND MIT（按文件/贡献划分，不是任选 MIT） | 保留完整 LICENSE，不把 AND 当成"二选一" |
| Dart `dbus`（Flutter 多平台依赖） | 0.7.15 | MPL-2.0 | 仅在实际打入对应平台产物时保留声明；Android APK 未打入则不适用 |

## 4. FFmpeg 特别说明（GPL-3.0-or-later）

- `imageio-ffmpeg` 的 Python 包装层为 BSD-2-Clause；但其在本机随包下载的 FFmpeg 7.1（Gyan essentials build）二进制编译时启用了 `--enable-gpl --enable-version3`，**二进制本身为 GPL-3.0-or-later**。
- 本项目通过 `subprocess` 以命令行方式启动独立 FFmpeg 进程、通过管道交换音频数据，**未在代码中链接 FFmpeg 库**。基于这种独立进程组合，团队自写 Python 源码不被要求整体改用 GPL。
- 当前 GitHub 源码树中**不包含** FFmpeg 二进制；云端服务器使用的 FFmpeg 构建未在本仓库核验。
- 如果后续发行物（容器镜像、完整后端运行包、APK 内打包 ffmpeg）包含该二进制，须单独遵守 GPL-3.0-or-later，提供对应源码获取方式，并在该发行物中附带 GPL 全文；本仓库的 MIT 文件不能覆盖 FFmpeg 二进制的 GPL 条款。

## 5. 模型与云服务

| 项目 | 许可 / 条款 | 说明 |
|---|---|---|
| BAAI/bge-small-zh-v1.5 | MIT（模型卡声明） | 向量编码；仓库不附带权重，首次运行从 Hugging Face 下载 |
| PaddleOCR / PaddlePaddle 模型资产 | 代码 Apache-2.0；**实际下载的 PP-OCRv6 权重须以 PaddleX/模型卡当时声明为准** | 代码许可不等于每个模型资产的许可 |
| 阿里云百炼 qwen3.7-plus / qwen3.8-flash / qwen3-asr-flash / qwen-audio-3.1-asr-flash | 云服务条款 | 按 API 调用使用，MIT 源码许可不构成对模型权重或云服务的授权 |

## 6. 前端 Flutter 依赖

前端锁定依赖见 `app_flutter/pubspec.lock`（约 143 项，含开发与多平台传递依赖，不等于 APK 实际打入数量）。初筛以 BSD/MIT/Apache-2.0 为主；其中 `jni 1.1.1`、`permission_handler_apple 9.6.4` 两项的精确版本许可原文本次未取得，**标记为待核实**，不作为"全部兼容"结论的一部分。

## 7. 素材图片（授权依据待补）

仓库包含以下视觉素材，**尚未取得书面授权依据**，在补齐前不主张其为可自由再分发的团队原创：

- `assets_src/original.png`
- `touxiang/touxiang1.png` ~ `touxiang4.png`
- `app_flutter/assets/` 下助手形象与头像等插画

需要素材提供者补充：作者、原创或生成/下载来源、原始许可、允许再分发的依据。裁剪、改色或改文件名不构成授权证明。在补齐前，这些素材不随公开仓库主张 MIT 再分发。

## 8. 知识库内容（不整库按 MIT 再分发）

`knowledge_base/` 共 203 篇文本，其中 116 篇附官方来源链接。需要说明：

- 团队依据公开资料整理的操作步骤、流程说明类内容，版权归团队。
- 引用 NHS 等外部来源的条目（如 `knowledge_base/health/冠心病与心绞痛急救.txt` 引用 NHS），其原文适用 NHS 网站条款（多数为 OGL，但含排除项与署名/改编要求）。**链接不等于再授权**，不能因标注了来源就把整库按 MIT 再分发。
- 完整 203 篇的逐篇授权比对本次未完成；在逐篇核验前，不做"知识库全部内容已兼容 MIT"的声明。
- 实际演示使用的是人工合成数据，不包含真实个人健康记录。

## 9. 云服务与密钥

- 百炼 API Key、和风天气 API Key、JWT `SECRET_KEY`、云服务器密码均保存在部署环境的 `.env`（0600 权限），不写入源码、不进入公开仓库。
- 演示账号与口令通过参赛平台允许的受限方式单独交付，不随源码公开。

## 10. 未覆盖范围

本文件不构成完整法律意见，未覆盖：Android APK 实际拆包后的原生依赖、构建工具链许可、云端部署环境、模型权重逐资产许可、知识库逐篇版权比对。如发行物形态变化（发布容器镜像、上架应用商店、提供完整后端安装包），须按对应形态重新核对并补充相应声明与源码提供方式。

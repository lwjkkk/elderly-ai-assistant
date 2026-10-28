# 前端服务目录

`api.dart` 保留为统一 HTTP、认证和服务端数据接口入口，路径及公开方法保持不变。调用者继续通过 `AppConfig.baseUrl` 和构建时的 `API_BASE` 选择后端，不把后端实现复制进前端。

| 目录 | 文件 | 职责 |
| --- | --- | --- |
| `chat/` | `chat_archive.dart`、`contest_answer.dart`、`drug_question.dart` | 本地会话归档、回答数据解析、查药提问 |
| `health/` | `family_alert_content.dart`、`vital_notification_status.dart`、`vital_validation.dart` | 家属提醒文案、体征通知状态和输入校验 |
| `medication/` | `medication_name.dart`、`medication_time.dart`、`medication_notification_service.dart` | 用药名称、服药时间和本地提醒 |
| `reports/` | `report_job_tracker.dart`、`report_retake.dart` | 报告上传任务轮询和重拍状态 |
| `voice/` | `answer_speech.dart`、`voice_transcription.dart`、`voice_transcription_ui.dart`、`voice_temp_cleanup*.dart` | 回答播报、录音转写、确认界面和临时文件清理 |
| `platform/` | `location_access.dart` | 定位及定位权限交互 |
| `platform/downloads/` | `file_download*.dart` | Web、原生平台和存根实现的文件保存入口 |

跨平台代码应导入 `platform/downloads/file_download.dart` 或 `voice/voice_temp_cleanup.dart`，由现有条件导入/导出选择平台实现。不要让页面直接引用 `_io.dart`、`_web.dart` 或 `_stub.dart`。

页面留在 `lib/pages/`；业务组件留在 `lib/widgets/`；共用视觉组件留在 `lib/afu/`。本次只归类文件并同步导入/导出路径，没有拆分 API 服务、修改业务代码或升级依赖。

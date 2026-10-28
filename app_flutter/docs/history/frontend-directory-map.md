# 前端目录迁移记录

日期：2026-10-28。整理基线为配色提交 `0e75329`，目录整理提交为 `0f79a3d`。本次迁移不改页面类名、业务逻辑或测试断言；只移动文件并同步 Dart 引用。

## 源码

路径均相对于 `app_flutter/`。

| 原路径 | 新路径 |
| --- | --- |
| `lib/pages/bind_page.dart` | `lib/pages/profile/bind_page.dart` |
| `lib/pages/chat_history_page.dart` | `lib/pages/chat/chat_history_page.dart` |
| `lib/pages/elder_home.dart` | `lib/pages/home/elder_home.dart` |
| `lib/pages/family_home.dart` | `lib/pages/home/family_home.dart` |
| `lib/pages/login_page.dart` | `lib/pages/auth/login_page.dart` |
| `lib/pages/register_page.dart` | `lib/pages/auth/register_page.dart` |
| `lib/pages/tabs/health_overview.dart` | `lib/pages/health/health_overview.dart` |
| `lib/pages/tabs/health_record_style.dart` | `lib/pages/health/health_record_style.dart` |
| `lib/pages/tabs/me_tab.dart` | `lib/pages/profile/me_tab.dart` |
| `lib/pages/tabs/med_form.dart` | `lib/pages/medication/med_form.dart` |
| `lib/pages/tabs/meds_tab.dart` | `lib/pages/medication/meds_tab.dart` |
| `lib/pages/tabs/placeholder_tab.dart` | `lib/pages/shared/placeholder_tab.dart` |
| `lib/pages/tabs/report_details.dart` | `lib/pages/health/report_details.dart` |
| `lib/pages/tabs/vital_alerts_page.dart` | `lib/pages/health/vital_alerts_page.dart` |
| `lib/pages/tabs/vital_draft_page.dart` | `lib/pages/health/vital_draft_page.dart` |
| `lib/pages/tabs/vitals_tab.dart` | `lib/pages/health/vitals_tab.dart` |

## 测试

| 原路径 | 新路径 |
| --- | --- |
| `test/backend_contract_test.dart` | `test/contracts/backend_contract_test.dart` |
| `test/chat_archive_test.dart` | `test/unit/chat_archive_test.dart` |
| `test/chat_history_widget_test.dart` | `test/widgets/chat_history_widget_test.dart` |
| `test/chat_lifecycle_test.dart` | `test/widgets/chat_lifecycle_test.dart` |
| `test/contest_contract_test.dart` | `test/contracts/contest_contract_test.dart` |
| `test/contest_draft_widget_test.dart` | `test/widgets/contest_draft_widget_test.dart` |
| `test/emergency_handoff_test.dart` | `test/widgets/emergency_handoff_test.dart` |
| `test/emergency_reported_question_test.dart` | `test/widgets/emergency_reported_question_test.dart` |
| `test/health_interactions_test.dart` | `test/widgets/health_interactions_test.dart` |
| `test/medication_time_test.dart` | `test/unit/medication_time_test.dart` |
| `test/privacy_age_alert_test.dart` | `test/widgets/privacy_age_alert_test.dart` |
| `test/report_ocr_handoff_test.dart` | `test/widgets/report_ocr_handoff_test.dart` |
| `test/vital_notification_status_test.dart` | `test/unit/vital_notification_status_test.dart` |
| `test/voice_input_test.dart` | `test/widgets/voice_input_test.dart` |
| `test/widget_test.dart` | `test/widgets/widget_test.dart` |

## 保留的目录与文件

- `lib/afu/`、`lib/services/`、`lib/widgets/` 保留原归属。
- `lib/pages/tabs/consult_drug_chat_tab.dart` 和 `hub_pages.dart` 仍含跨功能页面及导航状态，保留为聚合模块。
- Android/Web 工程、资源、依赖声明和锁文件未做调整。
- 本地 SDK 下载包、缓存、历史 APK、数据库和 `.env` 未搬迁或删除。

## 恢复

目录整理以独立提交保存。需要撤销时，在工作区干净的情况下使用 `git revert 0f79a3d`。配色提交 `0e75329` 与目录提交分开，撤销目录不会一并撤销配色。

如果还要撤销随后补充的说明文档，先撤销对应文档提交，再撤销目录提交；不要在目录已经恢复后继续使用新路径。

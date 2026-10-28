# 前端测试与目录整理报告

日期：2026-10-28（Asia/Shanghai）。目录整理提交：`0f79a3d`；独立配色提交：`0e75329`。

## 本轮范围

按用户最新要求，先整理前端目录，暂不构建 APK。迁移 16 个页面文件、分类 15 个测试文件，并同步导入路径。对迁移前后所有 Dart 文件进行比较，除导入/导出声明外，没有业务代码或测试断言的变更。完整映射见 [目录迁移记录](frontend-directory-map.md)。

当前工作副本实际有 15 个测试文件，并非参考清单中的 16 个。原先不存在 `app_flutter/tool/`；本次新增可复用的测试脚本及使用说明。

## 环境与命令

| 项目 | 实际环境 |
| --- | --- |
| 系统 | Windows x64 |
| Flutter | 3.47.5 stable |
| Dart | 3.13.4 |
| 依赖 | 使用现有 `pubspec.lock` 和已解析依赖，未升级版本 |

在仓库根目录运行：

```powershell
.\app_flutter\tool\check_frontend.ps1 -NoPub
```

该脚本实际调用 `flutter test test --reporter expanded --no-pub`。分类为 `unit/`（3 个文件）、`widgets/`（10 个文件）、`contracts/`（2 个文件）。

## 结果

| 检查 | 结果 |
| --- | --- |
| 整理前全量测试 | 88 项通过，0 项失败 |
| 整理后全量测试 | 88 项通过，0 项失败，通过率 100% |
| 本地 Dart 导入路径检查 | 无缺失目标 |
| 源码静态分析 | 0 错误、64 警告、161 条提示；诊断数量与整理前相同 |
| Web 调试构建 | 成功，退出码 0 |
| `git diff --check` | 通过 |

整理后实际测试日志末尾：

```text
00:14 +85: .../test/widgets/voice_input_test.dart: background and route removal release microphone without upload
00:14 +86: .../test/widgets/voice_input_test.dart: permission rejection offers text input and permanent rejection settings
00:15 +87: .../test/widgets/voice_input_test.dart: navigation during recording releases microphone and preserves new route
00:15 +88: All tests passed!
```

完整日志保留在本地 `app_flutter/build/frontend-checks/tests-all.log`，生成产物不提交 Git。该日志本次 SHA-256：

```text
2C71D7CB76EEBEBA4AB447718543670F3B3363018F6B08BB18FF42999197AC58
```

静态分析使用 `dart analyze --format machine lib`。分析器因现有警告返回退出码 2，因此此处只声明“无错误”，不声明静态检查完全无诊断。完整诊断保存于本地 `frontend-directory-analyze-20261028.log`。

Web 验证命令：

```powershell
cd app_flutter
flutter build web --debug --no-pub --dart-define=API_BASE=http://127.0.0.1:8000
```

产物位于本地 `app_flutter/build/web/`。本次为普通 JavaScript Web 构建；工具附带的 Wasm 预检查报告现有定位/TTS 依赖兼容问题，不代表已经通过 Wasm 构建。

## 验证边界

本轮未采集代码覆盖率，不以 100% 测试通过率代替代码覆盖率。接口契约测试使用模拟 HTTP 适配器，语音、通知等测试使用插件模拟；没有将结果表述为真实后端、真实相机/麦克风、手机权限或 APK 的验收。UI 截图、依赖许可证整理与 APK 交付留待目录整理后的阶段处理。

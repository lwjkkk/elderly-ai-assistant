# 前端测试目录

当前共有 15 个 `*_test.dart` 文件，按测试主要目的分类。文件内容中的测试用例和断言保持不变，仅同步页面搬迁后的导入路径。

| 目录 | 文件数 | 范围 |
| --- | ---: | --- |
| `unit/` | 3 | 聊天归档、用药时间窗口、体征通知状态 |
| `widgets/` | 10 | 登录、聊天历史/生命周期、语音输入、健康交互、紧急提示、年龄共享规则、报告重拍及草稿交互 |
| `contracts/` | 2 | API 参数、响应处理、报告任务、隐私设置和分层回答契约 |

```powershell
# 在 app_flutter 下运行。
flutter test
flutter test test/unit
flutter test test/widgets
flutter test test/contracts
flutter test test/widgets/widget_test.dart
```

所有组均使用 Flutter 测试运行器。接口契约测试中的 HTTP 适配器和相关插件使用模拟实现；通过这些测试不代表已经完成真实后端、相机、麦克风、通知权限或手机端验收。覆盖率需额外使用 `flutter test --coverage`，不能以测试通过率代替代码覆盖率。

# 云栖码梦 Flutter 前端

本分支 `front` 专门维护最新 Flutter 前端。Python 后端位于 [main 分支](https://github.com/lwjkkk/elderly-ai-assistant/tree/main)，通过 API 与前端连接。

| 目录 | 用途 |
| --- | --- |
| [app_flutter/](app_flutter/README.md) | Flutter 源码、Android/Web 工程、测试、资源及当前构建工具 |
| assets_src/、touxiang/ | 原始前端设计素材和头像来源 |
| [archive/legacy-tools/](archive/legacy-tools/README.md) | 旧修复与手机联调脚本，只保留历史，不作为当前启动入口 |

## 启动

```powershell
git clone --branch front --single-branch https://github.com/lwjkkk/elderly-ai-assistant.git elderly-ai-assistant-front
cd elderly-ai-assistant-front/app_flutter
flutter pub get
flutter run -d edge --dart-define=API_BASE=http://101.201.226.34:8000
```

在项目目录中可用 `flutter test` 运行测试。Android 打包、SDK 配置和后端地址说明见 [前端 README](app_flutter/README.md)。当前 Windows 打包入口为 `app_flutter/tool/build_apk.ps1`。

后续前端修改提交到 `front`，不要把整个前端分支合入后端 `main`。迁移范围、验证和撤回方式见 [分支分工记录](app_flutter/docs/branch-layout-20261028.md)。共享 API 契约见 [main 中的 API 文档](https://github.com/lwjkkk/elderly-ai-assistant/blob/main/docs/API接口文档.md)。

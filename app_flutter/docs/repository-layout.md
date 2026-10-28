# 前端维护边界与 Git 工作流

当前分工：`front` 保存最新前端；`main` / `backend` 保存后端；`feature/knowledge-base` 保持原样。此前把前端直接提交到 `main`、删除旧前端分支的做法已按用户要求纠正。旧记录仅说明当时的操作，后续以 [分支分工](branch-layout-20261028.md) 为准。

## 前端入口与目录

| 位置（front 分支） | 职责 |
| --- | --- |
| `app_flutter/lib/main.dart` | Flutter 入口，老人端和家属端共用 |
| `app_flutter/lib/pages/` | 页面、底部导航及聚合状态 |
| `app_flutter/lib/services/` | API、聊天、健康、用药、报告、语音和平台适配 |
| `app_flutter/lib/afu/`、`lib/widgets/` | 视觉组件与业务组件 |
| `app_flutter/android/`、`web/` | Android 和 Web 工程 |
| `app_flutter/test/` | 单元、组件与模拟接口契约测试 |
| `app_flutter/tool/` | 当前测试和 APK 构建工具 |
| `app_flutter/docs/` | 当前维护说明及历史验证记录 |
| `assets_src/`、`touxiang/` | 原始前端设计素材，保留原字节 |
| `archive/legacy-tools/` | 原混合仓库布局下的历史修复、手机联调工具，仅备查 |

后端入口 `main.py` 位于 `main` / `backend` 分支；前端入口 `app_flutter/lib/main.dart` 位于 `front` 分支。联调时使用两个独立目录或云端后端，不在当前工作目录反复切换前后端分支。

## 提交前端修改

```powershell
git fetch origin
git switch -c codex/frontend-next-task origin/front
# 仅修改前端文件后：
git status --short
git add -- app_flutter
git diff --cached --name-only
git diff --cached --check
git commit -m "fix(frontend): describe the change"
```

创建分支前保存已有未提交改动。前端 PR 以 `front` 为目标，不将整个 `front` 合入 `main`，否则会把前端文件重新带回后端分支。需要共享接口时以 `main` 中的 API 文档和服务端实际接口为准。

本轮移动分支归属时没有修改 Dart 代码、测试断言、依赖锁、平台工程或应用资源。聚合页面、缓存、已有 APK 和本地工作区均保留，不为整洁删除正在使用的文件。

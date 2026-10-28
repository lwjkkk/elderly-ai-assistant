# 前端维护边界与 Git 工作流

## 从哪里开始

| 位置 | 含义 | 本轮处理 |
| --- | --- | --- |
| `app_flutter/lib/main.dart` | Flutter 应用入口，老人端和家属端共用 | 保留入口，只同步服务导入 |
| `app_flutter/lib/pages/` | 页面及底部导航 | 保留现有功能分类 |
| `app_flutter/lib/services/` | 前端 API、领域辅助逻辑及平台服务 | 将 23 个平铺文件按职责分类 |
| `app_flutter/lib/afu/`、`lib/widgets/` | 视觉组件、业务组件 | 保留实现，同步引用 |
| `app_flutter/android/`、`web/` | Android、Web 平台工程 | 不修改 |
| `app_flutter/test/` | 单元、组件及模拟接口契约测试 | 只同步导入 |
| `app_flutter/tool/` | 测试、APK 构建工具 | 保留原命令和参数 |
| 仓库根目录 `main.py`、`web_app.py` | Python 后端入口 | 不修改、不搬迁 |
| 根目录 `api/`、`core/`、`services/`、`db/`、`backend/` 等 | 后端及其历史目录 | 不修改、不清理 |
| 根目录 `docs/`、`assets_src/`、`touxiang/` 和启动脚本 | 共享材料、素材来源及联调脚本 | 保留原文件和引用 |

路径在表格中均以仓库根目录为基准；`lib/widgets/` 等简写位于 `app_flutter/` 内。

本地根目录还存在一个空的 `frontend/`，在本轮开始时没有受 Git 跟踪的文件。它不是另一个有效前端工程，本次不删除这个本地目录。GitHub 的目录列表以受 Git 跟踪的文件为准，本地缓存不等于仓库源码。

## 判断历史文件

`build/`、`.dart_tool/`、`.pubcache/`、`flutter_pub_cache/`、SDK 下载压缩包和 APK 属于缓存、工具或构建产物，已有忽略规则，本轮保留。应用只使用 `pubspec.yaml` 声明的资源；根目录原始素材即使与应用头像相似，也不据此删除。

`lib/pages/tabs/hub_pages.dart` 与 `consult_drug_chat_tab.dart` 仍包含多个入口及共享导航状态，属于正在使用的聚合模块。未被某个入口直接使用的占位组件也不在本轮删除。文件名旧、体积大、存在相似代码，都不能单独证明文件可安全删除。

前端维护说明统一放 `app_flutter/docs/`，页面迁移、测试与打包的历史记录集中在 `app_flutter/docs/history/`。本地根目录 `docs/` 中已有的历史原件保留，本轮不改动共享材料。GitHub 发布只同步 `app_flutter/`，前端 README 的文档链接均指向该目录内部。

## 分支与目录

`main` 和 `frontend` 是 Git 分支名，目录名不会自动决定提交属于哪条分支。曾经直接提交到 `main` 的前端修改已经包含在对应提交里，不能通过删除文件、退回旧 `frontend` 分支或把旧目录覆盖回来整理历史。

本地整理阶段从已经验证过的 `5f21dfa` 创建 `codex/frontend-cleanup-20261028`，先建立空检查点提交 `c995cec`。开始时本地 `main` 与 `origin/main` 已分叉，已有 `frontend` 分支也是另一条历史线；这一阶段未合并、重置、重命名或删除这些分支，也未推送远端。

用户随后明确要求直接修改 GitHub。发布以远端 `main` 的 `acbccb7` 为父提交，只替换 `app_flutter/` 子树，其他路径沿用远端原树。发布时曾创建临时备份分支，用户随后指出旧前端分支仍未清理。本次将相关历史完整归档到本地 Git bundle 后，清理旧 `frontend`、旧前端修复分支和临时备份分支；远端交付入口统一为 `main`。发布与分支处理分别见 [发布说明](github-publication-20261028.md) 和 [分支清理记录](branch-cleanup-20261028.md)。

GitHub 发布后，后续前端改动应从最新 `origin/main` 创建任务分支，提交范围显式限定到前端。本地旧 `main` 和旧 `frontend` 不作为新任务起点：

```powershell
git fetch origin
git switch -c codex/frontend-next-task origin/main
# 修改 app_flutter/ 内的文件后：
git status --short
git add -- app_flutter
git diff --cached --name-only
git diff --cached --check
git commit -m "fix(frontend): describe the change"
```

创建分支前应先处理已有未提交改动；检查暂存列表，确认只有前端文件。向团队约定的目标分支提交 PR 时，只纳入已审核的前端提交。不要直接把旧 `frontend` 整条分支合入 `main`，也不要为整理目录强推。

## 撤回

本轮整理提交及检查结果记录在 [整理记录](cleanup-20261028.md)。使用 `git revert` 新增反向提交，可保留检查点和完整历史。执行前先提交或另行保存未提交改动；不要使用 `git reset --hard` 或清理命令删除本地文件。

如只需查看整理前代码，可创建另一个工作区，不改变当前运行目录：

```powershell
git worktree add --detach ..\frontend-before-cleanup c995cec
```

这条命令只是可选的人工恢复方式，本轮未创建该工作区。

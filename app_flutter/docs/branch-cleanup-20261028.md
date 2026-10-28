# 远端前端分支清理

日期：2026-10-28。用户指出旧前端分支落后、额外备份分支增加混乱，本轮将远端前端交付入口统一到 `main`，不再新增远端分支。

## 清理清单与原始位置

| 远端分支 | 原提交 | 处理 |
| --- | --- | --- |
| `frontend` | `d0de4e66647d413e296a2edbf0435bc813e78fd8` | 完整本地归档后删除旧远端分支 |
| `codex/frontend-health-fixes-20261013` | `b4a9cc5ef832c1043a8aa87b03d0adb94df4c92a` | 完整本地归档后删除旧远端分支 |
| `codex/backup-main-before-frontend-cleanup-20261028` | `acbccb737316cfa241faccc7e56d4fc6f8f6ff54` | 删除临时远端备份分支，改用本地归档 |
| `main` | 清理前为 `cd2feea2472a0893ecbc7551ecae6ce176160b7f` | 保留，作为统一前端交付入口；本轮只补充分支说明 |
| `backend` | `4c063e8295711d9e996c874b31b1c7cf49d2971f` | 保留且不改变提交位置 |
| `feature/knowledge-base` | `22df31ae3e2f6671bbe788c603fe178ba62f6f34` | 保留且不改变提交位置 |

两个旧前端分支相对当前 `main` 各有一条独有提交，不能将它们描述为已经全部合并。本轮不把旧代码覆盖到当前应用，也不合并其中的后端改动；这些提交的完整历史均已归档。分支清理只删除远端引用，不修改应用代码、依赖、配置、资源、数据库或后端文件。

## 已验证的本地归档

备份位于仓库本机路径 `app_flutter/build/branch-backups/20261028/`，由 Git 忽略，不上传 GitHub：

- `before-remote-branch-cleanup.bundle`：使用 `git bundle create --all` 保存本地和远端跟踪引用的完整历史。
- `branches-before.json`：记录六条远端分支的原始提交号和备份校验值。
- `verification.git/`：从 bundle 镜像还原的独立校验仓库。
- `bundle-verify.log`：归档校验日志。

Bundle SHA-256：`ceba0d5fe453ce01f04ae4db6524d634219db94aff5b8f9a33173c9d5bba8a86`。

删除前已完成 `git bundle verify`、从 bundle 执行镜像还原、`git fsck --full --no-dangling`，并逐条核对六条远端跟踪引用的提交号。清理使用带预期旧提交校验的原子删除，任一分支被并发更新时不覆盖、不强删。

## 恢复旧远端分支

如确有需要恢复旧 `frontend`，在本机仓库根目录执行：

```powershell
git fetch .\app_flutter\build\branch-backups\20261028\before-remote-branch-cleanup.bundle refs/remotes/origin/frontend:refs/heads/recovered-frontend
git push origin recovered-frontend:refs/heads/frontend
```

其他分支同理，从 bundle 中对应的 `refs/remotes/origin/<原分支名>` 恢复到新的本地分支，再按需推送回原远端名称。上述恢复命令本轮没有执行；本地原有分支也保留，没有删除本地工作区。

当前应用沿用此前已验证的整理结果：88 项前端测试通过，Web 与 Android Release 构建成功。本轮只修改维护文档和远端分支引用，不重构、不升级依赖、不重新部署。

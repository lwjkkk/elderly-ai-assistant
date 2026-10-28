# 完整项目展示版说明（2026-10-29）

`main` 现在作为评委查看的完整项目快照，保留现有后端根目录，并加入 `front` 分支中的 `app_flutter/`、`assets_src/`、`touxiang/` 和 `archive/`。没有把后端移动到新的 `backend/` 目录，也没有把 Flutter 工程改名，因此现有后端启动路径、知识库路径和前端工程路径保持不变。

## 分支职责

- `main`：完整项目展示和稳定版本。
- `backend`：后端开发分支。
- `front`：前端开发分支。

## 恢复

合并前的 `main`、`backend`、`front` 提交分别保存在 `backup/repo-integration-20261029/` 标签；完整 bundle 位于本地备份目录。合并后若需撤回，使用对应合并提交的 `git revert -m 1`，不要 reset 或强制推送。

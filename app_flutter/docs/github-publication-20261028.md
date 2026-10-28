# GitHub 前端整理发布

日期：2026-10-28（Asia/Shanghai）。用户在本地整理后明确授权直接连接 GitHub 修改。

## 范围

- 仓库：`lwjkkk/elderly-ai-assistant`；默认分支：`main`。
- 远端基线：`acbccb737316cfa241faccc7e56d4fc6f8f6ff54`。
- 发布时曾建立临时备份分支，指向该基线；随后按用户要求清理远端冗余分支，历史改用本地完整 Git bundle 保存，见 [分支清理记录](branch-cleanup-20261028.md)。
- 仅发布 `app_flutter/` 子树；仓库根目录及所有其他目录沿用远端原树，未改动后端、共享 README、历史脚本、素材或其他分支。
- 使用一个以远端基线为父节点的前端发布提交，更新前核对 `main` 的旧提交，不强制推送。

页面、服务和测试按职责归类，前端说明集中到 `app_flutter/docs/`。历史前端记录保存在 `docs/history/`，前端 README 不依赖尚未发布的根目录文档。

已验证的应用源码与本地整理结果保持一致；本次发布准备只补充文档、调整文档链接。88 项前端测试、Web 调试构建、Android Release 构建及代码等价检查结果见 [本地整理记录](cleanup-20261028.md)。GitHub 单次发布同时包含此前已验证的配色、页面和服务目录整理、测试分类及 Windows APK 构建工具，具体以发布提交的文件差异为准。

## 查看与恢复

在 GitHub 的 `main` 分支打开 `app_flutter/README.md`，即可查看最新目录说明。根目录后端历史文件按用户限制保持原状，因此这次更新不会重排整个仓库根目录。

撤回 GitHub 上本次更新，应对发布提交 `cd2feea2472a0893ecbc7551ecae6ce176160b7f` 执行 `git revert` 并正常推送反向提交，保留后续历史；不要强制把 `main` 指回旧提交。原始基线仍在 Git 提交历史中，并由本地 Git bundle 完整归档。

本地整理分支及原有本地 `main`、`frontend` 保留用于恢复；旧远端前端分支纳入本轮清理。后续开发先获取最新 `origin/main`，再创建任务分支；不要将旧本地 `main` 的分叉历史直接推回远端。

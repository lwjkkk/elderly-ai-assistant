# front / main 分支分工

日期：2026-10-28。按用户明确要求，保留并使用名为 `front` 的前端分支，将 `main` 中的前端内容迁入该分支。`main` 不再包含 Flutter 工程。

## 分工

| 分支 | 内容 |
| --- | --- |
| `front` | 最新 Flutter 工程、前端素材、前端测试文档及历史前端工具 |
| `main` | Python 后端、知识库及共享资料；只移出前端专属文件并更新 README 的前端导航 |
| `backend` | 保留原提交位置，不修改 |
| `feature/knowledge-base` | 保留原提交位置，不修改 |

前端工程继续使用 `app_flutter/` 路径，保持现有构建命令、资源路径与导入关系。`main.py` 的后端启动方式不变。需要同时运行两端时，分别检出 `front` 和 `main` 到两个目录，通过 `API_BASE` 连接。

## 迁移范围

- `app_flutter/`：完整迁入 `front`，仅更新分支维护说明；源码、测试、依赖、Android/Web 配置及资源原样保留。
- `assets_src/`、`touxiang/`：前端原始素材；未发现后端引用，原样迁入 `front`。
- `fix_notify.py`、`start_phone_test.ps1`、`start_phone_test.bat`：前端历史修复和手机打包工具，原字节保存在 `front` 的 `archive/legacy-tools/`。
- `docs/phone_test_runbook.md`：旧混合目录布局的手机联调记录，迁至上述历史工具目录。
- `docs/手机端验收测试文档.md`：前端验收文档，迁至 `app_flutter/docs/reference/phone-acceptance-20261009.md`。
- API、数据库、设计规范、知识库等共享材料保留在 `main`，不将后端文件搬迁或重构。

历史工具依赖旧的前后端共目录布局，只供备查，不作为分支拆分后的启动入口。当前使用 `app_flutter/tool/check_frontend.ps1`、`build_apk.ps1` 和前端 README 中的命令。

## 保全与验证

迁移前远端 `main` 为 `74e1a63e552b4fd392e1edde31edfb8c5137abb8`，本地检查点为 `567f0052e615e518502252ed6cc8ae8da49ce0e0`。

本地完整备份：`app_flutter/build/branch-split-20261028/before-front-main-split.bundle`，SHA-256 为 `b9eceeacb472ee8f930be89c23a74120f66415f8427dc8b17270d83c88254e41`，已通过 `git bundle verify`。不创建额外远端备份分支。

先提交并核验 `front` 中的完整代码，再从 `main` 移出对应文件；更新分支时核对旧提交，不强制覆盖其他人的提交。后端文件和前端运行文件以 Git blob 哈希逐一比较。此前该应用已通过 88 项前端测试、Web 调试构建及 Android Release 构建；本轮只改变分支和文件归属、维护说明，不改应用行为。

## 恢复

两次迁移提交均以迁移前的 `main` 为父节点，保留完整历史。若需恢复 `main` 的原混合目录，在 GitHub 或本地对本次 `main` 迁移提交执行 `git revert`，再正常推送，勿强制重置分支。实际提交号由本次交付的 GitHub 提交链接标识。

`front` 保留为前端维护分支，不再删除。已有本地工作目录、缓存、数据库与安装包均未删除或切换。

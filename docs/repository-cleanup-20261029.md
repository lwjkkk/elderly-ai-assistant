# 仓库分工与恢复记录（2026-10-29）

| 分支 | 职责 |
| --- | --- |
| main | 稳定后端、运行所需知识库及技术文档 |
| backend | 后端开发；与 main 保持相同运行目录结构 |
| front | Flutter 前端、资源、测试和构建工具 |

知识库原分支 feature/knowledge-base 的提交已包含在 main 的历史中，无未合并独有提交。删除分支不删除 main/backend 中的 203 篇知识文件，不覆盖或修改知识正文。

后端业务代码、配置、依赖、现行测试、部署脚本及知识库保留原路径和 Git blob。front 分支完全不变。backend 的旧前端工程从当前目录移出，原版本完整保存在备份标签；4 个历史前端工具/说明在 backend 的 archive/legacy-frontend-tools 中原样归档。

7 份无引用的历史记录统一存放 docs/dev-log；backend 已有相同内容，因此只移除重复路径。docs/self_test_results.md 由测试脚本引用，docs/后端修复验证_20261013.md 由证据索引引用，均保留。测试报告、证据索引、历史脚本 scripts/oneoff 及用途未确定的文件不进一步清理。

## 备份

操作前每个分支都建立了 backup/repo-cleanup-20261029/<分支名> 标签，准确提交号见同目录 repository-cleanup-20261029.json。完整仓库 bundle 已验证并从备份成功恢复四个分支、核对树哈希，git fsck 通过。

本地备份：outputs/repo-cleanup-20261029/before-cleanup.bundle。
SHA-256：714424cd655e24c2b9206d15c5da50b2461ce335bbfcf8afb9f9241a9ee91d7b。

本地原工作区及被忽略的数据库、环境、缓存均未移动或删除；bundle 只备份 Git 跟踪内容，不包含这些本地运行文件。

## 恢复知识库分支

在单独克隆的仓库中执行：

```bash
git fetch origin tag backup/repo-cleanup-20261029/feature/knowledge-base
git push origin refs/tags/backup/repo-cleanup-20261029/feature/knowledge-base:refs/heads/feature/knowledge-base
```

若该分支已被重新创建并推进，不强制覆盖，先核对新内容。

## 撤回整理

本次通过独立整理 PR 合并，先查看对应 PR 的合并提交。对普通单父提交使用 git revert <提交号>；对 merge 方式产生的合并提交使用 git revert -m 1 <合并提交号>。再通过正常 PR 合并恢复。按依赖逆序撤回，禁止 reset 或强制推送覆盖后续提交。

逐文件原路径、归档位置和 blob 哈希见 [整理清单](repository-cleanup-20261029.json)。归档文件必须与原 blob 一致；运行所需文件的路径、模式和 blob 必须全部一致。

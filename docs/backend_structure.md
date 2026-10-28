# 后端目录与测试入口

本次整理仅涉及后端脚本、测试和依赖清单，不移动 app_flutter 或修改业务路由。根目录的Python入口仅保留main.py与web_app.py，依赖入口为requirements.txt及requirements_lite.txt，另保留Postman集合。启动脚本移至scripts，开发和演示依赖放在requirements。README、pytest.ini、.gitignore、.env和本机运行数据库保留其必要位置。

| 位置 | 用途 |
| --- | --- |
| api core services db config utils | 现有后端模块，均已有 __init__.py |
| tests/unit | 默认自动回归，隔离数据库和外部服务 |
| tests/manual | 需人工选择的接口与解析脚本，不由 Pytest 自动执行 |
| tests/integration | 真实模型、OCR、账号或参数联测，显式启用 |
| tests/legacy | 旧阶段校验，可能含已删除接口或旧断言，不代表现行验收 |
| tests/fixtures | 本机 OCR 样本，图片不提交到仓库 |
| scripts | 回归入口、手工脚本入口、数据库初始化及运维工具 |
| docs | 技术文档、依赖发行包许可清单及测试说明 |

## 自动回归

在项目根目录执行：

```powershell
python -m pip install -r requirements/dev.txt
python scripts/run_tests.py
# 或
python scripts/run_tests.py
```

默认只收集 tests/unit。工作目录切到临时目录，数据库与上传内容使用测试夹具；禁止公网连接。真实 PDF 生成和音频解码仍使用实际依赖，模型及手机推送使用替身，不能把通过率解释为模型生成质量或通知送达率。

## 手工与真实服务联测

```powershell
python scripts/run_manual.py manual/test_spoken_vitals_draft.py
python scripts/run_manual.py --allow-external integration/test_chat.py
python scripts/run_manual.py --allow-external integration/test_agent.py --rag-only "医保卡怎么挂号"
```

手工脚本统一在一次性工作目录执行，不使用原有 elderly.db。旧脚本的测试账号不保证在隔离库存在；失败时需要更新夹具，不能改回真实用户库来凑通过。legacy 文件仅供历史参考。部分手工脚本有打印式结果，应同时核对 FAIL 数量，不能只看进程退出码。

真实联测可能使用现有模型额度。只使用人工合成或已获授权的数据；真实图片不自动上传到生成模型。本次目录整理没有执行这些真实模型联测。

## 数据库初始化与启动

```powershell
python scripts/init_db.py --database ./elderly.db
python main.py
```

main.py 的生命周期也会调用 init_db，完成建表与兼容迁移；初始化工具显式指定数据库，可重复运行。不会预置真实用户或账号。首次部署仍须配置 .env、模型缓存及运行依赖。

## 依赖和密钥

requirements.txt 为本次实际回归环境中25个直接运行依赖的版本快照；requirements_lite.txt 为兼容入口，并不声称缺少模型依赖也能运行完整功能。开发测试工具在 requirements/dev.txt，旧 Gradio 演示页的额外依赖在 requirements/web.txt。未再声明未实际使用的 LangChain、ChromaDB 或 DashScope SDK。

docs/backend_dependency_inventory.csv 记录本机发行包版本和许可元数据，供C整理开源清单；缺失许可仍须核对发行包LICENSE和上游，不将元数据当作法律认证。本次没有在全新虚拟环境中重新安装全部依赖或重跑真实模型。

.env 被忽略，.env.example 仅有空密钥和占位配置。部署时替换 SECRET_KEY，不能使用代码中的开发默认密钥。业务数据库、上传文件、模型权重和真实OCR样本仍留在本机并被忽略；不能因“不进仓库”而删除正在使用的数据。

一次性历史工具保存在scripts/oneoff并默认禁止运行。生成的Word、PPT、日志和测试证据不放在后端运行目录；如需留存，应在仓库外单独归档。前端素材与头像源文件保持现有位置。

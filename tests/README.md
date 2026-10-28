# 测试分类

默认 `python -m pytest` 或 `python scripts/run_tests.py` 只收集 unit，避免导入旧脚本时触发模型调用、建删库或写入历史报告。

manual、integration、legacy 使用 `python scripts/run_manual.py` 从项目根目录显式运行；integration 需要 `--allow-external`。旧脚本仅保留归档价值，不表示均兼容当前接口或全部已经复跑。

当前维护回归覆盖用药时间、提醒持久化、家属媒体、紧急风险及原话、录音转写、体检报告解析与综合接口合同。生成层和推送传输为替身的用例不计入真实模型质量测试。

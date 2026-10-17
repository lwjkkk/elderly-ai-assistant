# 本轮云端更新

手机包暂不重建，前端源码修改后需在后续统一打包时生效。

## 后端需要同步的文件

- `api/medication_recognition.py`：新增 `POST /api/meds/recognize-instructions`，说明书 OCR 只返回药名、单次用量、频次、明确写出的时间和 OCR 原文；不写入查药记录，也不直接创建提醒。用户核对表单并保存后，才由现有 `POST /api/meds` 创建用药安排。
- `main.py`：注册上述识别路由。
- `api/bind.py`：绑定列表返回对方真实的 `other_avatar`，取自对方服务端个人资料的 `avatar_url`。

不需要新增数据库表。OCR 环境沿用已有 `core.ocr`。

云服务器当前部署目录为 `/root/silver_agent_backend`。推荐在已登录的 Workbench 终端执行本轮专用更新脚本：

```bash
curl -fL --retry 3 https://raw.githubusercontent.com/lwjkkk/elderly-ai-assistant/main/scripts/deploy_cloud_patch_20261017.sh -o /tmp/update_elderly_backend.sh && bash /tmp/update_elderly_backend.sh
```

脚本只添加新识别接口，并在原有 main.py 和绑定接口中增补对应代码，保留云端其他配置。修改前备份原文件，不操作数据库、.env 和上传目录。重启后验证 OpenAPI 中存在新增接口，失败自动恢复原文件。如果原部署仍使用 nohup，脚本会切换为 systemd 常驻服务。

如果服务器无法连接 GitHub，可上传仓库中的脚本和 3 个后端文件后人工更新。源码推送成功不等于云端已部署，必须在服务器执行更新并完成公网验证。

## 手机后续实测

1. 未授权定位时启动 App：出现系统定位权限申请。永久拒绝时，App 提供进入系统设置的按钮；已授权则无需重复申请。
2. 两端咨询录音停止后：地址解析成功时自动填入推荐地址；无法解析时明确提示手动输入。
3. 用药拍照或选图：显示识别状态，回填用药表单并按频次生成提醒时间；保存后在用药提醒查看。家属长辈区查药仅展示 `kind=chat` 的 AI 对话查药记录。
4. AI 问事：点击话筒后讲话，文本实时出现在输入框；无系统识别服务、无权限或识别失败时显示具体提示。真机效果需后续 APK 验证。
5. 每次进入 AI 问事显示新会话；历史按钮保留旧版聊天及所有新会话。聊天历史保存在本机，退出账号不删除；卸载 App 或清除数据会移除本机历史。
6. 绑定对方已同步头像后，双方家人互动列表显示对方真实头像。若云端账号尚无头像，需由该账号登录新版 App 补传注册时选择的头像。

# 新云服务器 APK 构建记录

日期：2026-10-29（北京时间）。API_BASE：`http://47.93.97.48:8000`。

## 构建与产物

在 `app_flutter` 目录执行：

```powershell
.\tool\build_apk.ps1 -ApiBase http://47.93.97.48:8000 -AndroidSdk D:\AndroidSdk -GoogleMavenMirror https://maven.aliyun.com/repository/google -NoPub
```

- Release 构建成功，Gradle 用时 116.4 秒。
- APK：`app_flutter/build/app/outputs/flutter-apk/app-release.apk`（相对仓库根目录）。
- 大小：64,071,075 字节（约 61.1 MiB）。
- SHA-256：`FD025A536FF2A9E4EA564B3C68E8C341AC616999FAEC3A876777B2370ECEA91B`。
- 包名：`com.example.elderly_ai_assistant`；版本沿用 `1.0.0+1`。
- 最低 Android API 24，目标 API 36；包含 arm64-v8a、armeabi-v7a、x86_64。
- 沿用现有 Android Debug 演示签名，`apksigner verify --print-certs` 通过。
- 三种架构的 `libapp.so` 均包含新地址，均不含旧 IP `101.201.226.34`。

## 本次验证范围

- 新地址公网直连：首页 `/` 和 `/docs` 返回 200，匿名访问 `/api/meds` 返回 401。
- 配置与 README 差异检查通过。本次只更换后端地址和说明，没有重新执行前端全量测试。
- 未连接 Android 设备，未进行真机安装、登录和业务操作验收。
- README 中的 33 项真实业务检查、6 项公网检查和 2 个备用模型调用来自服务器部署验收说明，并非本次 APK 构建重新执行。
- 构建有 Gradle / AGP / Kotlin 未来兼容性提示，不影响本次成功产出；未改动工具链版本。

## 安装说明

旧 APK 不会自动切换服务器，需安装本次新包。新服务器没有迁移旧账号和用户文件，需使用新服务器账号登录。地址为 HTTP，当前服务器未配置 HTTPS。

构建日志：`app_flutter/build/apk-build/release.log`。APK 和日志属于本地构建产物，不提交 Git。

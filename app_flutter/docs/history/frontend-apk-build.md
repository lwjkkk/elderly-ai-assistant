# Android 云端演示包构建记录

日期：2026-10-28。后端地址：`http://101.201.226.34:8000`。

## 构建

在 `app_flutter` 目录运行：

```powershell
.\tool\build_apk.ps1 -ApiBase http://101.201.226.34:8000 -AndroidSdk D:\AndroidSdk -JavaHome 'D:\AndroidTools\jdk21\jdk-21.0.12.1+1' -GoogleMavenMirror https://maven.aliyun.com/repository/google -NoPub
```

环境：Flutter 3.47.5、Dart 3.13.4、Temurin JDK 21.0.12.1、Gradle Wrapper 8.14、AGP 8.11.1、Kotlin 2.2.20、Android SDK `D:\AndroidSdk`。依赖锁文件已记录于提交 `5011b36`。

脚本为当前进程设置 SDK、Java、资源下载源和系统 HTTP 代理；中文目录使用临时盘符，配合 Kotlin 进程内编译处理中文路径及跨盘符缓存问题，退出后恢复环境并移除映射。默认保留官方 Google Maven，本次通过显式参数使用阿里云镜像解决官方源 TLS 连接失败。未升级项目 Gradle 或修改系统设置。

## 产物与验证

- 文件：`app_flutter/build/app/outputs/flutter-apk/app-release.apk`。
- 大小：64,071,075 字节，Flutter 显示 61.1 MB。
- SHA-256：`CE78F89823D346B95002748E131D7E26CC7315884881C78F2B537934A6AA7B9A`。
- 应用：云栖码梦，`com.example.elderly_ai_assistant`，版本 `1.0.0+1`。
- 最低 Android API 24，目标 API 36；包含 `arm64-v8a`、`armeabi-v7a`、`x86_64`。
- Gradle Release 构建成功，`apksigner verify --print-certs` 校验通过。
- 逐个读取三种架构的 `libapp.so`，确认均包含上述云后端地址。
- `tool/check_frontend.ps1 -NoPub`：88 项前端测试全部通过。
- PowerShell 脚本语法解析、`git diff --check` 通过。

APK 使用现有 Android Debug 证书签名，供演示安装；正式发布需另配发布签名。本次未进行手机安装、登录、权限和云端业务联调。APK 和构建日志由 Git 忽略，提交中仅保存脚本、配置和说明。重新构建后的二进制哈希可能不同。

完整构建日志：`app_flutter/build/apk-build/release.log`；测试日志：`app_flutter/build/frontend-checks/tests-all.log`。

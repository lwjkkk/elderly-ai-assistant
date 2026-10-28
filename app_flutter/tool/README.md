# 前端工具

本次整理前，此工作副本没有 `app_flutter/tool/` 目录。这里新增的是可复用的开发工具，随源码提交；一次性验证输出写入已忽略的 `app_flutter/build/`。

## check_frontend.ps1

使用 PATH 中的 Flutter，在项目根目录或前端目录均可调用：

```powershell
# 全量测试；日志写入 app_flutter/build/frontend-checks/。
.\app_flutter\tool\check_frontend.ps1 -NoPub

# 只检查一个分类。
.\app_flutter\tool\check_frontend.ps1 -Group Unit -NoPub
.\app_flutter\tool\check_frontend.ps1 -Group Widgets -NoPub
.\app_flutter\tool\check_frontend.ps1 -Group Contracts -NoPub

# 可选覆盖率。
.\app_flutter\tool\check_frontend.ps1 -NoPub -Coverage

# Flutter 未加入 PATH 时显式指定。
.\app_flutter\tool\check_frontend.ps1 -FlutterCommand 'D:\flutter\bin\flutter.bat' -NoPub
```

默认允许 Flutter 按锁文件解析依赖；`-NoPub` 适用于已运行 `flutter pub get` 的环境。失败时脚本抛出错误，不把失败标成通过。脚本仅运行测试和保存日志，不修改依赖声明、不启动后端、不创建测试账号。

## build_apk.ps1

在前端目录运行，显式指定云端后端地址：

```powershell
.\tool\build_apk.ps1 -ApiBase http://101.201.226.34:8000 -AndroidSdk D:\AndroidSdk -GoogleMavenMirror https://maven.aliyun.com/repository/google -NoPub
```

Android SDK 路径依次从参数、`ANDROID_HOME`、`ANDROID_SDK_ROOT` 和 `android/local.properties` 读取。Java 可通过 `-JavaHome` 指定，否则使用 `JAVA_HOME` 或本机 `D:\AndroidTools\jdk21\` 中的 JDK 21。现有 Gradle 配置应使用兼容的 JDK 17/21；本机 Android Studio 自带的 JDK 25 不能用于直接运行当前 Gradle Wrapper。

项目路径含中文时，脚本自动选择空闲盘符，将项目临时映射到英文路径后构建，避免 Windows AOT 编译器无法读取中文路径中的 `app.dill`。脚本退出时移除自己创建的映射，并恢复环境变量；不搬动项目文件、不修改系统环境或 Flutter 全局设置。

映射构建时也临时关闭 Kotlin 增量编译，并在 Gradle 进程内编译 Kotlin，避免项目与插件缓存跨盘符、中文缓存路径在参数文件中被转义导致编译失败。

脚本默认临时使用 Flutter 官方资源源 `https://storage.googleapis.com`。本机原有清华镜像未提供当前引擎版本的 Android Release Maven 依赖；需要其他可达源时可传 `-FlutterStorageBaseUrl https://storage.flutter-io.cn`。该设置也会在退出时恢复。

如果 Windows 为该下载源配置了 HTTP 代理，脚本会将对应主机和端口临时传给 Gradle。这样 Java 的依赖下载可使用与系统一致的网络通道，结束后恢复原 `GRADLE_OPTS`。

本机 Google Maven 连接出现 TLS 握手失败，示例显式选择阿里云 Google Maven 镜像。网络能直连 Google 时可省略 `-GoogleMavenMirror`，项目默认仍使用 Google 官方仓库；此选项仅改变本次构建的 Google Maven 来源，不修改依赖版本。

成功后输出 APK 路径和 SHA-256，完整日志位于 `build/apk-build/release.log`。APK 和日志已被忽略，不提交 Git。当前 Android Release 使用调试签名，适用于演示测试；正式发布前需配置发布签名。

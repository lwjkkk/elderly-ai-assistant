# 云栖码梦 Flutter 前端

老人端和家属端共用的 Flutter 应用。当前仓库包含 Android 和 Web 工程；两个角色共用源码，登录后按服务端返回的角色进入首页。老人端和家属端目前均为 4 个 Tab，具体入口以 `lib/pages/home/` 为准。

## 目录

```text
app_flutter/
├── lib/
│   ├── main.dart              # 应用入口、主题、登录态和角色分流
│   ├── config.dart            # 编译时 API_BASE 配置
│   ├── theme.dart             # 全局主题和通用状态组件
│   ├── afu/                   # 共用视觉组件、插画、柔和色板及聊天气泡
│   ├── pages/
│   │   ├── auth/              # 登录、注册
│   │   ├── home/              # 老人端、家属端首页及底部导航
│   │   ├── chat/              # 聊天历史
│   │   ├── health/            # 健康总览、体征、报告及体征草稿
│   │   ├── medication/        # 用药列表、录药表单
│   │   ├── profile/           # 个人中心、家属绑定
│   │   ├── shared/            # 通用占位页面
│   │   └── tabs/              # 仍共用状态的问事/家庭/设置聚合页面
│   ├── services/
│   │   ├── api.dart           # 统一 API 入口，保留原路径
│   │   ├── chat/              # 聊天归档、回答模型、查药提问
│   │   ├── health/            # 体征校验、通知状态和家属提醒文案
│   │   ├── medication/        # 用药名称、时间和本地通知
│   │   ├── reports/           # 报告任务跟踪、重拍状态
│   │   ├── voice/             # 语音输入、回答播报和临时音频清理
│   │   └── platform/          # 定位及 downloads/ 跨平台文件下载
│   └── widgets/               # 年龄资料、回答证据、报告上传等业务组件
├── test/
│   ├── unit/                  # 纯逻辑测试
│   ├── widgets/               # 页面、交互和生命周期测试
│   └── contracts/             # 使用模拟适配器的接口契约测试
├── tool/                      # 可重复运行的前端检查脚本
├── docs/                      # 前端维护边界、Git 工作流和本轮整理记录
├── assets/                    # 助手、头像等静态资源
├── android/                   # Android 工程、权限和构建配置
├── web/                       # Web 入口和图标
├── pubspec.yaml               # 直接依赖、资源和版本声明
└── pubspec.lock               # 应用锁定的依赖版本，应提交 Git
```

`pages/tabs/` 的两个聚合文件同时承载多个入口和共享导航状态，本次只调整文件归属和引用，没有拆分其中的状态或业务逻辑。新增独立页面放入对应功能目录；多个页面共用的业务组件放 `widgets/`，共用视觉组件放 `afu/`。

`build/`、`.dart_tool/`、本地 IDE 配置、SDK 下载包和 APK 是本地文件或生成产物，不是源码目录，也不提交 Git。整理前已有的本地下载文件、缓存和构建产物均予以保留。

实际前端工程是本目录 `app_flutter/`，入口为 `lib/main.dart`；仓库根目录的 `main.py` 是后端入口。Git 的 `main`、`frontend` 是分支名，与目录职责不同，历史上提交到 `main` 的前端代码仍属于前端。目录职责、历史文件判断及安全的提交方式见 [仓库与分支说明](docs/repository-layout.md)，服务层文件归属见 [服务目录说明](lib/services/README.md)。

## 启动

在本目录执行：

```powershell
flutter pub get
flutter run -d edge --web-hostname 127.0.0.1 --web-port 8080 --dart-define=API_BASE=http://127.0.0.1:8000
```

后端需要另行在仓库根目录启动。前端的请求入口是 `lib/services/api.dart`，后端地址来自 `lib/config.dart` 中的 `AppConfig.baseUrl`。

## 后端地址

优先通过 `--dart-define=API_BASE=...` 配置，无需修改源码。未传入时默认 `http://10.0.2.2:8000`，只适用于 Android 模拟器访问本机后端。

| 场景 | `API_BASE` |
| --- | --- |
| 本机 Edge | `http://127.0.0.1:8000` |
| Android 模拟器 | `http://10.0.2.2:8000` |
| 同一局域网内的 Android 真机 | `http://电脑的局域网IP:8000` |
| 已部署后端 | 实际部署的 HTTPS 地址，例如 `https://api.example.com`（仅占位） |

真机上的 `127.0.0.1` 指向手机自身。局域网测试时后端需要监听电脑的局域网网卡，手机和电脑应互通。地址变更后需重新运行或构建应用；浏览器刷新不会更改已经编译进去的地址。API 密钥由后端管理，不写入 Flutter 源码或 `--dart-define`。

## 检查

```powershell
# 全量测试；Flutter 会递归发现分类目录中的 *_test.dart。
flutter test

# 单类测试。
flutter test test/unit
flutter test test/widgets
flutter test test/contracts

# Windows 下保留完整日志。
.\tool\check_frontend.ps1 -NoPub

# 可选：生成覆盖率文件 coverage/lcov.info。
.\tool\check_frontend.ps1 -NoPub -Coverage
```

测试分类见 [test/README.md](test/README.md)，工具参数见 [tool/README.md](tool/README.md)，本次检查结果见 [前端测试报告](docs/history/frontend-test-report.md)，旧路径对应关系见 [目录迁移记录](docs/history/frontend-directory-map.md)。

上述报告记录上一轮页面和测试目录整理；本轮服务层迁移及验证结果见 [2026-10-28 前端整理记录](docs/cleanup-20261028.md)。

## 版本恢复

目录调整与配色调整分别提交。查看和恢复时使用 Git，不删除现有目录：

```powershell
git log --oneline -- app_flutter
git show --stat <提交号>
git revert 0f79a3d
```

`git revert` 会新增一条反向提交，保留完整历史；执行前先提交或另行保存尚未提交的改动。

## Android APK

Android SDK 已安装但提示 `No Android SDK found` 时，应明确传入 SDK 路径。在本机前端目录执行：

```powershell
.\tool\build_apk.ps1 -ApiBase http://101.201.226.34:8000 -AndroidSdk D:\AndroidSdk -GoogleMavenMirror https://maven.aliyun.com/repository/google -NoPub
```

若尚未执行 `flutter pub get`，移除 `-NoPub`。也可在当前 PowerShell 中设置路径后直接使用 Flutter：

```powershell
$env:ANDROID_HOME = 'D:\AndroidSdk'
$env:ANDROID_SDK_ROOT = 'D:\AndroidSdk'
$env:JAVA_HOME = 'D:\AndroidTools\jdk21\jdk-21.0.12.1+1'
flutter build apk --release --dart-define=API_BASE=http://101.201.226.34:8000
```

当前中文项目路径请优先使用上面的 `build_apk.ps1`：脚本还会通过临时盘符避开 Windows AOT 编译器的中文路径问题，构建结束后自动撤销映射。安装包位于 `build/app/outputs/flutter-apk/app-release.apk`，当前使用调试签名供演示测试。工具说明见 [tool/README.md](tool/README.md)。修改构建时后端地址后需要重新打包。

本次安装包的版本、校验值及验证范围见 [Android 构建记录](docs/history/frontend-apk-build.md)。

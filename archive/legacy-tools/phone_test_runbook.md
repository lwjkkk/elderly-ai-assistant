# Phone Test Runbook

## Current setup

- Flutter app: `app_flutter`
- Android SDK: `D:\AndroidSdk`
- Flutter SDK: `D:\flutter`
- Backend port: `8000`
- The backend listens on `0.0.0.0`
- The phone APK must use the computer's current LAN IPv4 address

## Tomorrow: one-click startup

Double-click:

```text
D:\云栖码梦\start_phone_test.bat
```

The script will:

1. Detect the current LAN IPv4 address.
2. Start the backend if port `8000` is not already listening.
3. Rebuild the debug APK only when the LAN IP has changed.
4. Copy the result to `app_flutter\build\app\outputs\flutter-apk\phone-test.apk`.
5. Open the APK folder.

The phone and computer must be on the same Wi-Fi network.

## One-time firewall setup

If the phone cannot open the health check URL, open PowerShell as Administrator and run:

```powershell
cd D:\云栖码梦
.\allow_api_8000_admin.ps1
```

Then open this URL on the phone, replacing the IP with the one printed by the startup script:

```text
http://<computer-lan-ip>:8000/
```

Expected response:

```json
{"message":"老年数字辅助智能体后端运行正常"}
```

## Current APK

The already-built phone APK is:

```text
D:\云栖码梦\app_flutter\build\app\outputs\flutter-apk\云栖码梦-真机版.apk
```

The computer's current LAN IP when this record was written was `172.20.10.5`.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$appRoot = Join-Path $root "app_flutter"
$flutter = "D:\flutter\bin\flutter.bat"
$javaHome = "C:\Program Files\Android\Android Studio\jbr"
$androidSdk = "D:\AndroidSdk"
$python = Join-Path $root ".venv\Scripts\python.exe"
$buildRoot = Join-Path $appRoot "build"
$apkSource = Join-Path $buildRoot "app\outputs\flutter-apk\app-debug.apk"
$apkTarget = Join-Path $buildRoot "app\outputs\flutter-apk\phone-test.apk"
$apiMarker = Join-Path $buildRoot "phone-api-base.txt"
$backendOut = Join-Path $buildRoot "phone-backend.out.log"
$backendErr = Join-Path $buildRoot "phone-backend.err.log"
$port = 8000

function Get-LanIp {
    try {
        $default = Get-NetIPConfiguration -ErrorAction Stop |
            Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
            ForEach-Object { $_.IPv4Address.IPAddress } |
            Where-Object { $_ -notmatch "^(127\.|169\.254\.)" } |
            Select-Object -First 1
        if ($default) {
            return $default
        }
    } catch {
    }

    $matches = ipconfig | Select-String -Pattern "IPv4.*:\s*(\d{1,3}(?:\.\d{1,3}){3})"
    foreach ($match in $matches) {
        if ($match.Matches.Count -eq 0) {
            continue
        }
        $candidate = $match.Matches[0].Groups[1].Value
        if ($candidate -notmatch "^(127\.|169\.254\.|192\.168\.92\.|192\.168\.42\.)") {
            return $candidate
        }
    }

    throw "Could not find a usable LAN IPv4 address."
}

function Test-PortOpen {
    try {
        return [bool](Test-NetConnection "127.0.0.1" -Port $port -InformationLevel Quiet)
    } catch {
        return $false
    }
}

if (-not (Test-Path $python)) {
    throw "Python virtual environment not found: $python"
}
if (-not (Test-Path $flutter)) {
    throw "Flutter not found: $flutter"
}
if (-not (Test-Path $androidSdk)) {
    throw "Android SDK not found: $androidSdk"
}

$lanIp = Get-LanIp
$apiBase = "http://$lanIp`:$port"
$env:JAVA_HOME = $javaHome
$env:ANDROID_SDK_ROOT = $androidSdk
$env:ANDROID_HOME = $androidSdk
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.googleapis.com"
$env:PATH = "$javaHome\bin;$androidSdk\platform-tools;$androidSdk\cmdline-tools\bin;$env:PATH"
$env:GRADLE_OPTS = "-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=10808 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=10808"

if (-not (Test-PortOpen)) {
    New-Item -ItemType Directory -Force $buildRoot | Out-Null
    try {
        Start-Process `
            -FilePath $python `
            -ArgumentList "main.py" `
            -WorkingDirectory $root `
            -WindowStyle Hidden `
            -RedirectStandardOutput $backendOut `
            -RedirectStandardError $backendErr | Out-Null
    } catch {
        Start-Process `
            -FilePath $python `
            -ArgumentList "main.py" `
            -WorkingDirectory $root `
            -WindowStyle Hidden | Out-Null
    }

    for ($i = 0; $i -lt 30 -and -not (Test-PortOpen); $i++) {
        Start-Sleep -Seconds 1
    }
}

if (-not (Test-PortOpen)) {
    throw "Backend did not start on port $port. Check $backendErr"
}

$needsBuild = $true
if ((Test-Path $apkSource) -and (Test-Path $apiMarker)) {
    $needsBuild = ((Get-Content $apiMarker -Raw).Trim() -ne $apiBase)
}

if ($needsBuild) {
    Push-Location $appRoot
    try {
        & $flutter build apk --debug --no-pub "--dart-define=API_BASE=$apiBase"
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter APK build failed."
        }
    } finally {
        Pop-Location
    }
    Set-Content -LiteralPath $apiMarker -Value $apiBase -Encoding ASCII
}

Copy-Item -LiteralPath $apkSource -Destination $apkTarget -Force
Write-Host ""
Write-Host "Phone test is ready." -ForegroundColor Green
Write-Host "API: $apiBase"
Write-Host "APK: $apkTarget"
Write-Host "Health check: $apiBase/"
Write-Host ""
Start-Process explorer.exe -ArgumentList "/select,`"$apkTarget`""

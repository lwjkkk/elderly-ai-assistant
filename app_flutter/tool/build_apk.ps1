[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [uri]$ApiBase,
    [string]$AndroidSdk,
    [string]$JavaHome,
    [string]$FlutterCommand = 'flutter',
    [string]$FlutterStorageBaseUrl = 'https://storage.googleapis.com',
    [uri]$GoogleMavenMirror,
    [switch]$NoPub
)

$ErrorActionPreference = 'Stop'
if (-not $ApiBase.IsAbsoluteUri -or $ApiBase.Scheme -notin @('http', 'https')) {
    throw 'ApiBase must be an absolute HTTP or HTTPS backend URL.'
}
if ($GoogleMavenMirror -and (-not $GoogleMavenMirror.IsAbsoluteUri -or $GoogleMavenMirror.Scheme -ne 'https')) {
    throw 'GoogleMavenMirror must be an absolute HTTPS repository URL.'
}
$appRoot = Split-Path -Parent $PSScriptRoot
$flutter = (Get-Command $FlutterCommand -ErrorAction Stop).Source

if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_HOME }
if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
if (-not $AndroidSdk) {
    $localProperties = Join-Path $appRoot 'android\local.properties'
    if (Test-Path -LiteralPath $localProperties) {
        $sdkLine = Get-Content -LiteralPath $localProperties |
            Where-Object { $_ -match '^\s*sdk\.dir\s*=' } | Select-Object -First 1
        if ($sdkLine) {
            $AndroidSdk = $sdkLine.Split('=', 2)[1].Trim().Replace('\\', '\').Replace('\:', ':')
        }
    }
}
if (-not $AndroidSdk -or -not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'platform-tools\adb.exe'))) {
    throw 'Android SDK not found. Supply -AndroidSdk with the installed SDK directory.'
}

if (-not $JavaHome) { $JavaHome = $env:JAVA_HOME }
if (-not $JavaHome) {
    $localJdks = 'D:\AndroidTools\jdk21'
    if (Test-Path -LiteralPath $localJdks) {
        $jdk = Get-ChildItem -LiteralPath $localJdks -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe') } |
            Select-Object -First 1
        if ($jdk) { $JavaHome = $jdk.FullName }
    }
}
if ($JavaHome -and -not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin\java.exe'))) {
    throw 'Java not found in JavaHome. Supply -JavaHome with a compatible JDK directory.'
}

$savedEnvironment = @{}
foreach ($name in @('ANDROID_HOME', 'ANDROID_SDK_ROOT', 'JAVA_HOME', 'PATH', 'FLUTTER_STORAGE_BASE_URL', 'GRADLE_OPTS')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$logRoot = Join-Path $appRoot 'build\apk-build'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$logFile = Join-Path $logRoot 'release.log'
$buildArguments = @('build', 'apk', '--release', "--dart-define=API_BASE=$($ApiBase.AbsoluteUri.TrimEnd('/'))")
if ($NoPub) { $buildArguments += '--no-pub' }

$mappedDrive = $null
$locationPushed = $false
try {
    $buildRoot = $appRoot
    # Windows AOT snapshot tools cannot read some non-ASCII source paths.
    # SUBST creates an alias; it does not move or copy the project.
    if ($appRoot -match '[^\x00-\x7F]') {
        $drive = @('R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z') |
            Where-Object { -not (Test-Path -LiteralPath "${_}:\") } |
            Select-Object -First 1
        if (-not $drive) { throw 'No free drive letter available for the temporary build alias.' }
        & subst.exe "${drive}:" (Split-Path -Parent $appRoot)
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the temporary build drive.' }
        $mappedDrive = "${drive}:"
        $buildRoot = Join-Path "${drive}:\" (Split-Path -Leaf $appRoot)
        Write-Host "Temporary build path: $buildRoot"
    }
    Push-Location $buildRoot
    $locationPushed = $true
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
    $env:FLUTTER_STORAGE_BASE_URL = $FlutterStorageBaseUrl
    if ($GoogleMavenMirror) {
        $env:GRADLE_OPTS = "$env:GRADLE_OPTS -Dorg.gradle.project.googleMavenMirror=$($GoogleMavenMirror.AbsoluteUri.TrimEnd('/'))"
        Write-Host "Google Maven mirror: $GoogleMavenMirror"
    }
    if ($mappedDrive) {
        # Pub/Gradle caches may be on a different drive or contain Chinese paths.
        # Avoid Kotlin's cross-root incremental cache and escaped argument files.
        $env:GRADLE_OPTS = "$env:GRADLE_OPTS -Dorg.gradle.project.kotlin.incremental=false -Dorg.gradle.project.kotlin.compiler.execution.strategy=in-process"
    }
    # Java/Gradle does not automatically inherit the Windows HTTP proxy.
    $storageUri = [uri]$FlutterStorageBaseUrl
    $proxy = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy($storageUri)
    if ($proxy -and $proxy.Host -ne $storageUri.Host -and $proxy.Scheme -eq 'http') {
        $env:GRADLE_OPTS = "$env:GRADLE_OPTS -Dhttp.proxyHost=$($proxy.Host) -Dhttp.proxyPort=$($proxy.Port) -Dhttps.proxyHost=$($proxy.Host) -Dhttps.proxyPort=$($proxy.Port)"
        Write-Host "Using Windows HTTP proxy for Gradle: $($proxy.Host):$($proxy.Port)"
    }
    $env:PATH = "$(Join-Path $AndroidSdk 'platform-tools');$env:PATH"
    if ($JavaHome) {
        $env:JAVA_HOME = $JavaHome
        $env:PATH = "$(Join-Path $JavaHome 'bin');$env:PATH"
    }
    & $flutter @buildArguments 2>&1 | Tee-Object -FilePath $logFile
    if ($LASTEXITCODE -ne 0) { throw "APK build failed. See $logFile" }
    $apkPath = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path -LiteralPath $apkPath)) { throw "APK output not found: $apkPath" }
    Write-Host "APK: $apkPath"
    Write-Host "SHA256: $((Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash)"
} finally {
    if ($locationPushed) { Pop-Location }
    if ($mappedDrive) { & subst.exe $mappedDrive /d }
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}

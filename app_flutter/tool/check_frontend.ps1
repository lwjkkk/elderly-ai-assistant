[CmdletBinding()]
param(
    [ValidateSet('All', 'Unit', 'Widgets', 'Contracts')]
    [string]$Group = 'All',
    [string]$FlutterCommand = 'flutter',
    [switch]$NoPub,
    [switch]$Coverage
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
$flutter = (Get-Command $FlutterCommand -ErrorAction Stop).Source
$logRoot = Join-Path $appRoot 'build\frontend-checks'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$logFile = Join-Path $logRoot ("tests-{0}.log" -f $Group.ToLowerInvariant())

$testTarget = if ($Group -eq 'All') { 'test' } else { 'test/' + $Group.ToLowerInvariant() }
$flutterArguments = @('test', $testTarget, '--reporter', 'expanded')
if ($NoPub) { $flutterArguments += '--no-pub' }
if ($Coverage) { $flutterArguments += '--coverage' }

Push-Location $appRoot
try {
    Write-Host "Running Flutter tests: $testTarget"
    & $flutter @flutterArguments 2>&1 | Tee-Object -FilePath $logFile
    $testExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0) {
        throw "Flutter tests failed (exit $testExitCode). See $logFile"
    }
    Write-Host "Tests passed. Log: $logFile"
    if ($Coverage) {
        Write-Host "Coverage: $(Join-Path $appRoot 'coverage\lcov.info')"
    }
} finally {
    Pop-Location
}

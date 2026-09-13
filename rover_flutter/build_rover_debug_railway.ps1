param(
    [int]$BuildNumber = 2
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Test-Path -LiteralPath '.env.local')) {
    throw 'Missing Flutter .env.local configuration.'
}

$apiUrl = 'https://rover-production-d220.up.railway.app'
Write-Host "Building ROVER debug 1.0.0+$BuildNumber against $apiUrl"
$flutterArgs = @(
    'build', 'apk', '--debug',
    '--dart-define-from-file=.env.local',
    "--dart-define=ROVER_API_BASE_URL=$apiUrl",
    '--dart-define=ROVER_PHASE13_ENABLED=true',
    '--dart-define=ROVER_AI_LENS_OCR=true',
    '--dart-define=ROVER_PHASE15_ENABLED=true',
    '--dart-define=ROVER_PHASE16_ENABLED=true',
    '--build-name=1.0.0',
    "--build-number=$BuildNumber"
)
flutter @flutterArgs
if ($LASTEXITCODE -ne 0) {
    throw 'Debug APK build failed. Do not install an older APK from the output folder.'
}
Write-Host "Debug APK: $PSScriptRoot\build\app\outputs\flutter-apk\app-debug.apk"

param(
    [string]$DeviceId = "RFGYA0RB5HY",
    [string]$EnvFile = ".env.local",
    [switch]$SkipAdbReverse,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

Set-Location -LiteralPath $PSScriptRoot
Write-Host "ROVER project: $PSScriptRoot" -ForegroundColor Cyan

function Import-RoverEnvFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing $Path. Copy .env.example to .env.local and add your local values."
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            return
        }

        $separatorIndex = $line.IndexOf("=")
        if ($separatorIndex -le 0) {
            return
        }

        $name = $line.Substring(0, $separatorIndex).Trim()
        $value = $line.Substring($separatorIndex + 1).Trim()
        $value = $value.Trim('"').Trim("'")
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

Import-RoverEnvFile -Path $EnvFile

if ([string]::IsNullOrWhiteSpace($env:ROVER_API_BASE_URL)) {
    $env:ROVER_API_BASE_URL = "http://127.0.0.1:5080"
}

if ([string]::IsNullOrWhiteSpace($env:ROVER_DEV_USER)) {
    $env:ROVER_DEV_USER = "field-test"
}

if ([string]::IsNullOrWhiteSpace($env:MAPBOX_PUBLIC_TOKEN)) {
    throw "MAPBOX_PUBLIC_TOKEN is missing in $EnvFile."
}

if (-not $env:MAPBOX_PUBLIC_TOKEN.StartsWith("pk.")) {
    throw "MAPBOX_PUBLIC_TOKEN must be a Mapbox public token that starts with pk."
}

if ($ValidateOnly) {
    Write-Host "Flutter Rover environment is configured."
    exit 0
}

if (-not $SkipAdbReverse) {
    & adb -s $DeviceId reverse tcp:5080 tcp:5080
    if ($LASTEXITCODE -ne 0) {
        throw "USB connection failed. Unlock the phone, allow USB debugging, and confirm adb devices shows 'device' before retrying."
    }
}

flutter run -d $DeviceId --debug `
    "--dart-define-from-file=$EnvFile" `
    --dart-define=ROVER_API_BASE_URL=$env:ROVER_API_BASE_URL `
    --dart-define=ROVER_DEV_USER=$env:ROVER_DEV_USER `
    --dart-define=MAPBOX_PUBLIC_TOKEN=$env:MAPBOX_PUBLIC_TOKEN `
    --dart-define=ROVER_PHASE15_ENABLED=true `
    --dart-define=ROVER_PHASE16_ENABLED=true

exit $LASTEXITCODE

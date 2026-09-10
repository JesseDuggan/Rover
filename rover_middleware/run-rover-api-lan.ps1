param(
    [string]$Configuration = "Debug",
    [string]$EnvFile = ".env.local",
    [string]$LanIp,
    [switch]$DisableRouteStories,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

function Test-PrivateIpv4 {
    param([System.Net.IPAddress]$Address)

    $bytes = $Address.GetAddressBytes()
    return $bytes.Length -eq 4 -and (
        $bytes[0] -eq 10 -or
        ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168)
    )
}

function Get-RoverLanIpv4 {
    $candidates = Get-NetIPConfiguration | ForEach-Object {
        $configuration = $_
        $_.IPv4Address | ForEach-Object {
            if (Test-PrivateIpv4 -Address $_.IPAddress) {
                [PSCustomObject]@{
                    Address = $_.IPAddress.IPAddressToString
                    HasGateway = $null -ne $configuration.IPv4DefaultGateway
                    InterfaceMetric = $configuration.NetIPv4Interface.InterfaceMetric
                }
            }
        }
    }

    $selected = $candidates |
        Sort-Object @{ Expression = 'HasGateway'; Descending = $true }, InterfaceMetric |
        Select-Object -First 1

    if ($null -eq $selected) {
        throw "No active private IPv4 address was found. Connect Wi-Fi or enable Windows Mobile Hotspot, then run this script again."
    }

    return $selected.Address
}

$envPath = Join-Path $scriptRoot $EnvFile
if (Test-Path -LiteralPath $envPath) {
    Get-Content -LiteralPath $envPath | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            return
        }

        $separator = $line.IndexOf("=")
        if ($separator -le 0) {
            return
        }

        $name = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim().Trim('"').Trim("'")
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
    Write-Host "Loaded environment from $envPath"
}

$localFeatureDefaults = @{
    ROVER_PHASE15_ENABLED = "true"
    ROVER_PHASE15_CORRIDOR_ENABLED = "true"
    ROVER_PHASE16_ENABLED = "true"
    ROVER_PHASE15_EVENTS_ENABLED = "true"
    ROVER_PHASE15_CURRENT_INFO_ENABLED = "true"
}
foreach ($entry in $localFeatureDefaults.GetEnumerator()) {
    $value = if ($DisableRouteStories) { "false" } else { $entry.Value }
    [Environment]::SetEnvironmentVariable($entry.Key, $value, "Process")
}

if ([string]::IsNullOrWhiteSpace($LanIp)) {
    $lanIp = Get-RoverLanIpv4
} else {
    $parsedLanIp = $null
    if (-not [System.Net.IPAddress]::TryParse($LanIp, [ref]$parsedLanIp) -or -not (Test-PrivateIpv4 -Address $parsedLanIp)) {
        throw "LanIp must be a private IPv4 address such as 192.168.1.25 or 192.168.137.1."
    }
    $lanIp = $parsedLanIp.IPAddressToString
}
$localUrl = "http://127.0.0.1:5080"
$lanUrl = "http://${lanIp}:5080"

$env:ASPNETCORE_ENVIRONMENT = "Development"

Write-Host ""
Write-Host "ROVER API wireless development" -ForegroundColor Cyan
Write-Host "Local API:        $localUrl"
Write-Host "Laptop LAN IPv4: $lanIp"
Write-Host "Phone health:     $lanUrl/health" -ForegroundColor Green
Write-Host "Listening on:     http://0.0.0.0:5080"
$routeStoryStatus = if ($DisableRouteStories) { "disabled" } else { "Phase 16 enabled" }
Write-Host "Route stories:    $routeStoryStatus" -ForegroundColor Green
Write-Host ""
Write-Host "This script does not change Windows Firewall or router settings."
Write-Host "Keep port 5080 limited to the Windows Private network profile."
Write-Host ""

if ($ValidateOnly) {
    exit 0
}

dotnet run --project .\Rover.Api\Rover.Api.csproj `
    --configuration $Configuration `
    --no-launch-profile `
    --urls "http://0.0.0.0:5080"

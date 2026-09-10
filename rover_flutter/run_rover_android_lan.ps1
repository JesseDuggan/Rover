param(
    [string]$LaptopIp,
    [string]$DeviceId,
    [string]$EnvFile = ".env.local",
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

function ConvertTo-RoverPrivateIpv4 {
    param([string]$Value)

    $candidate = $Value.Trim()
    [System.Uri]$uri = $null
    if ([System.Uri]::TryCreate($candidate, [System.UriKind]::Absolute, [ref]$uri) -and
        ($uri.Scheme -eq "http" -or $uri.Scheme -eq "https")) {
        $candidate = $uri.Host
    }

    [System.Net.IPAddress]$address = $null
    if (-not [System.Net.IPAddress]::TryParse($candidate, [ref]$address) -or -not (Test-PrivateIpv4 -Address $address)) {
        throw "LaptopIp '$Value' is not a private IPv4 address. Use the address or full Phone health URL printed by run-rover-api-lan.ps1."
    }

    return $address
}

function Get-RoverLanIpv4 {
    $candidates = Get-NetIPConfiguration | ForEach-Object {
        $configuration = $_
        $_.IPv4Address | ForEach-Object {
            if (Test-PrivateIpv4 -Address $_.IPAddress) {
                [PSCustomObject]@{
                    Address = $_.IPAddress
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
        throw "No active private IPv4 address was found. Pass -LaptopIp using the Phone health URL printed by the API launcher."
    }

    return $selected.Address
}

$resolvedLaptopIp = if ([string]::IsNullOrWhiteSpace($LaptopIp)) {
    [string](Get-RoverLanIpv4)
} else {
    $LaptopIp
}
$parsedIp = ConvertTo-RoverPrivateIpv4 -Value $resolvedLaptopIp
$apiIp = $parsedIp.ToString()
if ([string]::IsNullOrWhiteSpace($apiIp)) {
    throw "ROVER could not determine the laptop IPv4 address. Pass -LaptopIp using the Phone health URL printed by the API launcher."
}

$envPath = (Resolve-Path -LiteralPath $EnvFile).Path
$apiBaseUrl = "http://${apiIp}:5080"

Write-Host "ROVER API: $apiBaseUrl" -ForegroundColor Cyan
Write-Host "Health:    $apiBaseUrl/health"
Write-Host "USB reverse is not used. The Android device must be on the same private network."

if ($ValidateOnly) {
    exit 0
}

$flutterArgs = @(
    "run",
    "--debug",
    "--dart-define-from-file=$envPath",
    "--dart-define=ROVER_API_BASE_URL=$apiBaseUrl",
    "--dart-define=ROVER_PHASE15_ENABLED=true",
    "--dart-define=ROVER_PHASE16_ENABLED=true"
)
if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
    $flutterArgs += @("-d", $DeviceId)
}

flutter @flutterArgs

param(
    [string]$Urls = "http://127.0.0.1:5080",
    [string]$Configuration = "Release",
    [string]$EnvFile = ".env.local",
    [switch]$DisableRouteStories
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

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
        $value = $line.Substring($separator + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
    Write-Host "Loaded environment from $envPath"
} else {
    Write-Host "No $EnvFile found. Running with existing process environment."
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

$routeStoryStatus = if ($DisableRouteStories) { "disabled" } else { "Phase 16 enabled" }
Write-Host "Route stories: $routeStoryStatus" -ForegroundColor Green

dotnet run --project .\Rover.Api\Rover.Api.csproj --configuration $Configuration --urls $Urls

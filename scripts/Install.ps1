param(
    [string]$ModulePath = (Join-Path $env:ProgramFiles 'PowerShell/Modules/SystemDashboard'),
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [string]$ServiceName = 'SystemDashboardTelemetry'
)

Write-Host 'Installing SystemDashboard module...'

if (-not (Test-Path $ModulePath)) {
    New-Item -ItemType Directory -Path $ModulePath -Force | Out-Null
}
Copy-Item -Path "$PSScriptRoot/Start-SystemDashboard.psm1" -Destination $ModulePath -Force
Copy-Item -Path "$PSScriptRoot/Start-SystemDashboard.psd1" -Destination $ModulePath -Force
Copy-Item -Path "$PSScriptRoot/tools/SystemDashboard.Telemetry.psm1" -Destination (Join-Path $ModulePath 'SystemDashboard.Telemetry.psm1') -Force

# Ensure runtime directories exist
$runtimeDirs = @('var/syslog', 'var/asus', 'var/staging', 'var/log')
foreach ($dir in $runtimeDirs) {
    $fullPath = Join-Path $PSScriptRoot $dir
    if (-not (Test-Path -LiteralPath $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    }
}

Write-Host 'Setting up Python virtual environment...'
python -m venv "$PSScriptRoot/.venv"
if ($IsWindows) {
    & "$PSScriptRoot/.venv/Scripts/pip" install -r "$PSScriptRoot/requirements.txt"
} else {
    & "$PSScriptRoot/.venv/bin/pip" install -r "$PSScriptRoot/requirements.txt"
}

if ($IsWindows) {
    Write-Host 'Registering SystemDashboard telemetry service...'
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $serviceScript = (Resolve-Path (Join-Path $PSScriptRoot 'services/SystemDashboardService.ps1')).Path
    $resolvedConfig = (Resolve-Path $ConfigPath).Path
    $binary = "`"$serviceScript`""

    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Service $ServiceName already exists. Attempting to stop and delete..."
        try {
            if ($existing.Status -ne 'Stopped') {
                Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
                $existing.WaitForStatus('Stopped', (New-TimeSpan -Seconds 15)) | Out-Null
            }
        }
        catch {
            Write-Warning "Failed to stop existing service $ServiceName $_"
        }
        & sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
    }

    New-Service -Name $ServiceName -BinaryPathName $binary -DisplayName 'System Dashboard Telemetry Service' -StartupType Automatic -ErrorAction Stop | Out-Null
    Write-Host "Service $ServiceName registered. Use Start-Service $ServiceName to begin ingestion."
}

param(
    [string]$ModulePath = (Join-Path $env:ProgramFiles 'PowerShell/Modules/SystemDashboard'),
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
)

Write-Host 'Installing SystemDashboard module...'

if (-not (Test-Path $ModulePath)) {
    New-Item -ItemType Directory -Path $ModulePath -Force | Out-Null
}
Copy-Item -Path "$PSScriptRoot/Start-SystemDashboard.psm1" -Destination $ModulePath -Force
Copy-Item -Path "$PSScriptRoot/Start-SystemDashboard.psd1" -Destination $ModulePath -Force

Write-Host 'Setting up Python virtual environment...'
python -m venv "$PSScriptRoot/.venv"
if ($IsWindows) {
    & "$PSScriptRoot/.venv/Scripts/pip" install -r "$PSScriptRoot/requirements.txt"
} else {
    & "$PSScriptRoot/.venv/bin/pip" install -r "$PSScriptRoot/requirements.txt"
}

if ($IsWindows) {
    Write-Host 'Registering SystemDashboard service...'
    $pwsh = (Get-Command pwsh).Source
    $cmd = "`"$pwsh`" -NoProfile -Command `"Import-Module SystemDashboard; Start-SystemDashboard -ConfigPath '$ConfigPath'`""
    New-Service -Name 'SystemDashboard' -BinaryPathName $cmd -StartupType Automatic -ErrorAction SilentlyContinue | Out-Null
}

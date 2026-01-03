#!/usr/bin/env pwsh
# Create a desktop/start menu shortcut to the System Dashboard UI.

param(
    [ValidateSet('Desktop', 'StartMenu', 'Both')]
    [string]$Target = 'Desktop',
    [string]$Url
)

$rootPath = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $rootPath "config.json"
$dashboardUrl = $Url

if (-not $dashboardUrl -and (Test-Path $configPath)) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($config.Prefix) {
            $dashboardUrl = $config.Prefix
        }
    } catch {
        $dashboardUrl = $null
    }
}

if (-not $dashboardUrl) {
    $dashboardUrl = "http://localhost:15000/"
}

$targets = @()
if ($Target -eq 'Desktop' -or $Target -eq 'Both') {
    $targets += [Environment]::GetFolderPath('Desktop')
}
if ($Target -eq 'StartMenu' -or $Target -eq 'Both') {
    $targets += (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs")
}

foreach ($folder in $targets) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    $shortcutPath = Join-Path $folder "SystemDashboard.url"
    @(
        "[InternetShortcut]"
        "URL=$dashboardUrl"
    ) | Set-Content -LiteralPath $shortcutPath -Encoding ascii
    Write-Host "Created shortcut: $shortcutPath" -ForegroundColor Green
}

### BEGIN FILE: Invoke-DataSourceCollection.ps1
#requires -Version 5.1
param(
    [string]$StagingDirectory = './var/staging'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Use safe path resolution (works in PS 5.1+)
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    # fallback for older hosts
    $scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}

# Resolve staging dir relative to this script location
if (-not [System.IO.Path]::IsPathRooted($StagingDirectory)) {
    $StagingDirectory = Join-Path -Path $scriptRoot -ChildPath $StagingDirectory
}

# Load DataSourceManager module
$dsModulePath = Join-Path -Path $scriptRoot -ChildPath 'tools\DataSourceManager.psm1'
if (-not (Test-Path $dsModulePath)) {
    throw "❌ DataSourceManager module not found at: $dsModulePath"
}

try {
    Import-Module $dsModulePath -Force
}
catch {
    throw "❌ Failed to import module: $dsModulePath — $($_.Exception.Message)"
}

# Create manager and register default sources
$manager = Initialize-DataSourceManager -StagingDirectory $StagingDirectory

Write-Verbose "Resolved staging dir to: $StagingDirectory"
Write-Verbose "Registered sources:"
foreach ($src in $manager.Sources.GetEnumerator()) {
    $state = if ($src.Value.Enabled) { 'ENABLED' } else { 'DISABLED' }
    Write-Verbose ("  - {0} ({1}) [{2}]" -f $src.Key, $src.Value.Type, $state)
}

# Run the collection
try {
    Write-Host "🚀 Collecting from all enabled data sources..." -ForegroundColor Cyan
    $manager.CollectFromAllSources()
    Write-Host "✅ Complete. Check '$StagingDirectory' for JSON payloads." -ForegroundColor Green
}
catch {
    Write-Host "❌ Collection failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
### END FILE: Invoke-DataSourceCollection.ps1

#!/usr/bin/env pwsh
<#
.SYNOPSIS
Download Npgsql and required dependencies for LAN collector.
.DESCRIPTION
Downloads NuGet packages directly (no PackageManagement dependency) into the repo lib/ folder.
#>

[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $PSScriptRoot '..\lib'),
    [string]$NpgsqlVersion = '8.0.3',
    [string]$LoggingVersion = '8.0.0',
    [string]$DiagnosticSourceVersion = '8.0.0'
)

$ErrorActionPreference = 'Stop'

function Download-Package {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$OutDir
    )

    $fileName = "$Id.$Version.nupkg"
    $targetPath = Join-Path $OutDir $fileName
    if (Test-Path -LiteralPath $targetPath) {
        Write-Host "Already downloaded: $fileName" -ForegroundColor Yellow
        return
    }

    $url = "https://www.nuget.org/api/v2/package/$Id/$Version"
    Write-Host "Downloading $Id $Version..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $targetPath -UseBasicParsing
    Write-Host "Saved: $targetPath" -ForegroundColor Green
}

if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

Download-Package -Id 'Npgsql' -Version $NpgsqlVersion -OutDir $Destination
Download-Package -Id 'Microsoft.Extensions.Logging.Abstractions' -Version $LoggingVersion -OutDir $Destination
Download-Package -Id 'System.Diagnostics.DiagnosticSource' -Version $DiagnosticSourceVersion -OutDir $Destination

Write-Host "Done. Restart the LAN collector scheduled task." -ForegroundColor Green

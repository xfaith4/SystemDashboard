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

function Ensure-PackageExtracted {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$OutDir
    )

    $packageName = "$Id.$Version"
    $packagePath = Join-Path $OutDir "$packageName.nupkg"
    if (-not (Test-Path -LiteralPath $packagePath)) {
        Write-Host "Package not found: $packagePath" -ForegroundColor Yellow
        return
    }

    $extractDir = Join-Path $OutDir $packageName
    $needsExtract = -not (Test-Path -LiteralPath $extractDir)
    if (-not $needsExtract) {
        $dll = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter "$Id.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $dll) {
            $needsExtract = $true
        }
    }

    if ($needsExtract) {
        Write-Host "Extracting $packageName..." -ForegroundColor Cyan
        if (Test-Path -LiteralPath $extractDir) {
            Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Expand-Archive -LiteralPath $packagePath -DestinationPath $extractDir -Force
        Write-Host "Extracted to: $extractDir" -ForegroundColor Green
    }
}

if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

Download-Package -Id 'Npgsql' -Version $NpgsqlVersion -OutDir $Destination
Download-Package -Id 'Microsoft.Extensions.Logging.Abstractions' -Version $LoggingVersion -OutDir $Destination
Download-Package -Id 'System.Diagnostics.DiagnosticSource' -Version $DiagnosticSourceVersion -OutDir $Destination

Ensure-PackageExtracted -Id 'Npgsql' -Version $NpgsqlVersion -OutDir $Destination
Ensure-PackageExtracted -Id 'Microsoft.Extensions.Logging.Abstractions' -Version $LoggingVersion -OutDir $Destination
Ensure-PackageExtracted -Id 'System.Diagnostics.DiagnosticSource' -Version $DiagnosticSourceVersion -OutDir $Destination

Write-Host "Done. Restart the LAN collector scheduled task." -ForegroundColor Green

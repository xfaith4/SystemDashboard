#!/usr/bin/env pwsh
<#
.SYNOPSIS
Setup environment variables for System Dashboard

.DESCRIPTION
This script sets up the required environment variables for the System Dashboard application.
It can set variables for the current session or permanently for the user.

.PARAMETER Permanent
Set environment variables permanently for the current user

.EXAMPLE
.\scripts\setup-environment.ps1
Set variables for current session only

.EXAMPLE
.\scripts\setup-environment.ps1 -Permanent
Set variables permanently for current user
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Set environment variables permanently for the current user")]
    [switch]$Permanent
)

# Get the directory where this script is located
$ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

# Define environment variables
$EnvVars = @{
    'ROUTER_LOG_PATH' = Join-Path $ScriptDirectory 'sample-router.log'
    'SYSTEMDASHBOARD_ROOT' = $ScriptDirectory
}

Write-Host "🔧 Setting up System Dashboard environment variables..." -ForegroundColor Cyan

foreach ($VarName in $EnvVars.Keys) {
    $VarValue = $EnvVars[$VarName]

    # Set for current session
    Set-Item -Path "Env:$VarName" -Value $VarValue
    Write-Host "✅ Set $VarName = $VarValue" -ForegroundColor Green

    # Set permanently if requested
    if ($Permanent) {
        [Environment]::SetEnvironmentVariable($VarName, $VarValue, [EnvironmentVariableTarget]::User)
        Write-Host "   → Saved permanently for user" -ForegroundColor Yellow
    }
}

if ($Permanent) {
    Write-Host "`n⚠️  Permanent variables will be available in new PowerShell sessions" -ForegroundColor Yellow
    Write-Host "   Current session already has the variables set" -ForegroundColor Yellow
} else {
    Write-Host "`n💡 To make these variables permanent, run:" -ForegroundColor Blue
    Write-Host "   .\scripts\setup-environment.ps1 -Permanent" -ForegroundColor Blue
}

Write-Host "`n🧪 Running validation to verify setup..." -ForegroundColor Cyan
python validate-environment.py

[CmdletBinding()]
param(
    [Parameter()][string]$Payload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "No-op action executed." -ForegroundColor Green

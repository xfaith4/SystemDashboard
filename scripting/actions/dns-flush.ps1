[CmdletBinding()]
param(
    [Parameter()][string]$Payload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Flushing DNS cache..." -ForegroundColor Cyan
ipconfig /flushdns | Out-String | Write-Host
Write-Host "DNS cache flushed." -ForegroundColor Green

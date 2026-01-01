#requires -Version 7
<#
.SYNOPSIS
Run a one-time health check and request GPT suggestions when unhealthy.
.DESCRIPTION
Calls the legacy listener /api/health endpoint. If unhealthy, sends a
redacted snapshot of context and code snippets to a GPT endpoint.
#>
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.json'),
    [int]$StartupDelaySeconds = 10,
    [string]$HealthPath = '/api/health'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot 'var\log'
$logFile = Join-Path $logDir 'auto-heal.log'
$responseFile = Join-Path $logDir 'auto-heal-response.json'

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-AutoHealLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding ascii
}

function Resolve-ConfigPrefix {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return 'http://localhost:15000/'
    }
    try {
        $cfg = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ($cfg.Prefix) {
            return [string]$cfg.Prefix
        }
    } catch {
        return 'http://localhost:15000/'
    }
    return 'http://localhost:15000/'
}

function Build-HealthUrl {
    param([string]$Prefix, [string]$Path)
    $trimmedPrefix = $Prefix.TrimEnd('/')
    $trimmedPath = $Path.TrimStart('/')
    return "$trimmedPrefix/$trimmedPath"
}

function Redact-Object {
    param([object]$Value)
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string] -or $Value -is [int] -or $Value -is [double] -or $Value -is [bool]) {
        return $Value
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [hashtable])) {
        $out = @()
        foreach ($item in $Value) {
            $out += Redact-Object $item
        }
        return $out
    }
    if ($Value -is [hashtable]) {
        $out = @{}
        foreach ($key in $Value.Keys) {
            $out[$key] = Redact-Object $Value[$key]
        }
        return $out
    }
    $out = @{}
    foreach ($prop in $Value.PSObject.Properties) {
        $name = $prop.Name
        if ($name -match '(password|secret|token|apikey|api_key)') {
            $out[$name] = '[REDACTED]'
        } else {
            $out[$name] = Redact-Object $prop.Value
        }
    }
    return $out
}

function Get-RedactedConfig {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return '{}'
    }
    try {
        $cfg = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $redacted = Redact-Object $cfg
        return ($redacted | ConvertTo-Json -Depth 10)
    } catch {
        return '{}'
    }
}

function Get-FileSnippet {
    param(
        [string]$Path,
        [string]$Pattern
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return "Missing file: $Path"
    }
    $matches = Select-String -Path $Path -Pattern $Pattern -Context 3,3
    if (-not $matches) {
        return "No matches for '$Pattern' in $Path"
    }
    $out = @()
    foreach ($match in $matches) {
        $start = $match.LineNumber - $match.Context.PreContext.Count
        $lines = $match.Context.PreContext + $match.Line + $match.Context.PostContext
        $out += "File: $Path"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $out += ("{0}: {1}" -f ($start + $i), $lines[$i])
        }
        $out += ""
    }
    return ($out -join "`n")
}

$enabled = $env:SYSTEMDASHBOARD_AUTOHEAL_ENABLED
if ($enabled -and $enabled.ToLower() -in @('0','false','no')) {
    Write-AutoHealLog "Auto-heal disabled via SYSTEMDASHBOARD_AUTOHEAL_ENABLED."
    return
}

if ($StartupDelaySeconds -gt 0) {
    Start-Sleep -Seconds $StartupDelaySeconds
}

$prefix = Resolve-ConfigPrefix -Path $ConfigPath
$healthUrl = Build-HealthUrl -Prefix $prefix -Path $HealthPath

try {
    $response = Invoke-WebRequest -Uri $healthUrl -TimeoutSec 10 -ErrorAction Stop -SkipHttpErrorCheck
} catch {
    Write-AutoHealLog "Health check request failed: $($_.Exception.Message)"
    return
}

if (-not $response.Content) {
    Write-AutoHealLog "Health check returned empty body."
    return
}

try {
    $health = $response.Content | ConvertFrom-Json
} catch {
    Write-AutoHealLog "Health check returned non-JSON content."
    return
}

if ($health.ok -eq $true) {
    Write-AutoHealLog "Health check OK."
    return
}

$apiKey = $env:OPENAI_API_KEY
if (-not $apiKey) {
    Write-AutoHealLog "OPENAI_API_KEY not set; skipping GPT call."
    return
}

$endpoint = if ($env:SYSTEMDASHBOARD_AI_ENDPOINT) { $env:SYSTEMDASHBOARD_AI_ENDPOINT } else { 'https://api.openai.com/v1/chat/completions' }
$model = if ($env:SYSTEMDASHBOARD_AI_MODEL) { $env:SYSTEMDASHBOARD_AI_MODEL } else { 'gpt-4o-mini' }

$redactedConfig = Get-RedactedConfig -Path $ConfigPath

$snippets = @()
$snippets += Get-FileSnippet -Path (Join-Path $repoRoot 'Start-SystemDashboard.psm1') -Pattern 'api/health|api/timeline|api/devices/summary|Invoke-PostgresJsonQuery|Test-PostgresQuery'
$snippets += Get-FileSnippet -Path (Join-Path $repoRoot 'wwwroot\app.js') -Pattern 'loadHealthStatus|HEALTH_ENDPOINT|renderHealthBanner|api/health'
$snippets += Get-FileSnippet -Path (Join-Path $repoRoot 'wwwroot\index.html') -Pattern 'health-banner'
$snippets += Get-FileSnippet -Path (Join-Path $repoRoot 'wwwroot\styles.css') -Pattern 'health-banner'

$prompt = @"
Health check failed at: $healthUrl
HTTP status: $($response.StatusCode)
Health payload:
$($health | ConvertTo-Json -Depth 6)

Redacted config.json:
$redactedConfig

Relevant code snippets:
$($snippets -join "`n")

Please propose targeted code fixes with file paths and brief reasoning. Avoid broad refactors.
"@

$body = @{
    model = $model
    messages = @(
        @{
            role = 'system'
            content = 'You are a senior engineer. Provide concise code fixes with file paths and minimal risk.'
        },
        @{
            role = 'user'
            content = $prompt
        }
    )
    temperature = 0.2
}

try {
    Write-AutoHealLog "Sending GPT request to $endpoint using model $model."
    $result = Invoke-RestMethod -Method Post -Uri $endpoint -Headers @{
        Authorization = "Bearer $apiKey"
        'Content-Type' = 'application/json'
    } -Body ($body | ConvertTo-Json -Depth 8) -TimeoutSec 60
    $result | ConvertTo-Json -Depth 8 | Out-File -FilePath $responseFile -Encoding utf8
    Write-AutoHealLog "GPT response saved to $responseFile."
} catch {
    Write-AutoHealLog "GPT request failed: $($_.Exception.Message)"
}

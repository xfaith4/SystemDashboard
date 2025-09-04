<#
.SYNOPSIS
  Stub for invoking saved prompts. Always succeeds for local testing.

.DESCRIPTION
  Accepts -PromptId, -Input, and/or -FromFile. Echos inputs and exits 0.
  Replace this stub with your real script when ready.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)] [string] $PromptId,
  [Parameter(Mandatory=$false)] [string] $Input,
  [Parameter(Mandatory=$false)] [string] $FromFile
)

Write-Host "--- Invoke-SavedPrompt (stub) ---"
if ($PSBoundParameters.ContainsKey('PromptId')) {
  Write-Host ("PromptId       : {0}" -f $PromptId)
}

if ($PSBoundParameters.ContainsKey('Input')) {
  Write-Host ("Input (raw)    : {0}" -f $Input)
}

$fromFilePreview = $null
if ($PSBoundParameters.ContainsKey('FromFile') -and $FromFile) {
  if (Test-Path -LiteralPath $FromFile) {
    try {
      $content = Get-Content -LiteralPath $FromFile -Raw -ErrorAction Stop
      $preview = $content.Substring(0, [Math]::Min(200, [Math]::Max(0, $content.Length)))
      $fromFilePreview = $preview -replace "\r?\n", ' '
      Write-Host ("FromFile       : {0}" -f (Resolve-Path -LiteralPath $FromFile))
      Write-Host ("FromFile bytes : {0}" -f ([Text.Encoding]::UTF8.GetByteCount($content)))
      Write-Host ("FromFile head  : {0}" -f $fromFilePreview)
    }
    catch {
      Write-Warning ("Failed reading FromFile: {0}" -f $_)
    }
  } else {
    Write-Warning ("FromFile path not found: {0}" -f $FromFile)
  }
}

Write-Host "Result          : SUCCESS (stub)"
exit 0


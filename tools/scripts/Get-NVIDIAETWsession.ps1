# Requires: Admin PowerShell
# Goal: See the NVIDIA ETW session, then stop it to clear the warning.

# List active ETW trace sessions (look for NVIDIA-NVTOPPS-FILTER)
logman query -ets

# Show details for just this session (buffer sizes, file size, mode, etc.)
logman query "NVIDIA-NVTOPPS-FILTER" -ets

# Stop the session (ends logging; warning clears)
logman stop "NVIDIA-NVTOPPS-FILTER" -ets

# Stop the telemetry sessions
logman stop "NVIDIA-NVTOPPS-FILTER" -ets
logman stop "NVIDIA-NVTOPPS-NOCAT" -ets

# Disable FrameView service so it doesn’t restart the trace
Get-Service FrameViewSDK -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Service $_.Name -Force
    Set-Service $_.Name -StartupType Disabled
}

# Confirm it’s gone or circular now
logman query "NVIDIA-NVTOPPS-FILTER" -ets
logman query "NVIDIA-NVTOPPS-NOCAT" -ets

# Quick pulse — time span + volume
$EvtxPath = "F:\Downloads\SecurityEventLogs.evtx"
$first = Get-WinEvent -Path $EvtxPath -MaxEvents 1 -Oldest
$last  = Get-WinEvent -Path $EvtxPath -MaxEvents 1
"{0} → {1}" -f $first.TimeCreated, $last.TimeCreated

# Top 15 Event IDs (what dominates the log?)
Get-WinEvent -Path $EvtxPath | Group-Object Id | Sort-Object Count -Desc | Select-Object -First 15

# Failed logons (4625) by Account
Get-WinEvent -FilterHashtable @{Path=$EvtxPath; Id=4625} |
  ForEach-Object {[xml]$_.ToXml()} |
  Group-Object { $_.Event.EventData.Data | Where-Object {$_.Name -eq 'TargetUserName'} | ForEach-Object { $_.'#text' } } |
  Sort-Object Count -Desc | Select-Object -First 10

# Account lockouts (4740)
Get-WinEvent -FilterHashtable @{Path=$EvtxPath; Id=4740} | Measure-Object
Get-WinEvent -FilterHashtable @{Path=$EvtxPath; Id=4740} |
  ForEach-Object {[xml]$_.ToXml()} |
  Group-Object { $_.Event.EventData.Data | Where-Object {$_.Name -eq 'TargetUserName'} | ForEach-Object { $_.'#text' } } |
  Sort-Object Count -Desc | Select-Object -First 10

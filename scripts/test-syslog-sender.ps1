# Test Syslog Sender
# Sends test syslog messages to verify the UDP listener is working

param(
    [string]$TargetIP = "127.0.0.1",
    [int]$Port = 5514,
    [int]$Count = 5,
    [string]$Facility = "local0",
    [string]$Severity = "info",
    [string]$Source = "test-sender"
)

function Send-SyslogMessage {
    param(
        [string]$Message,
        [string]$TargetIP,
        [int]$Port,
        [string]$Facility = "local0",
        [string]$Severity = "info",
        [string]$Source = "test-sender"
    )

    # Syslog facility and severity mappings
    $facilities = @{
        "kern" = 0; "user" = 1; "mail" = 2; "daemon" = 3; "auth" = 4;
        "syslog" = 5; "lpr" = 6; "news" = 7; "uucp" = 8; "cron" = 9;
        "authpriv" = 10; "ftp" = 11; "local0" = 16; "local1" = 17;
        "local2" = 18; "local3" = 19; "local4" = 20; "local5" = 21;
        "local6" = 22; "local7" = 23
    }

    $severities = @{
        "emerg" = 0; "alert" = 1; "crit" = 2; "err" = 3;
        "warning" = 4; "notice" = 5; "info" = 6; "debug" = 7
    }

    $facilityCode = $facilities[$Facility] ?? 16  # Default to local0
    $severityCode = $severities[$Severity] ?? 6   # Default to info
    $priority = $facilityCode * 8 + $severityCode

    $timestamp = Get-Date -Format "MMM dd HH:mm:ss"
    $hostname = [System.Environment]::MachineName

    # RFC3164 format: <priority>timestamp hostname source: message
    $syslogMessage = "<$priority>$timestamp $hostname ${Source}: $Message"

    try {
        $udpClient = [System.Net.Sockets.UdpClient]::new()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($syslogMessage)
        $endpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($TargetIP), $Port)

        $udpClient.Send($bytes, $bytes.Length, $endpoint) | Out-Null
        $udpClient.Close()

        Write-Host "✅ Sent: $syslogMessage" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "❌ Failed to send: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main execution
Write-Host "🧪 Syslog Test Sender" -ForegroundColor Cyan
Write-Host "=" * 20
Write-Host "Target: ${TargetIP}:${Port}" -ForegroundColor Yellow
Write-Host "Facility: $Facility, Severity: $Severity" -ForegroundColor Yellow
Write-Host "Source: $Source" -ForegroundColor Yellow
Write-Host ""

$successCount = 0

for ($i = 1; $i -le $Count; $i++) {
    $message = "Test syslog message #$i from PowerShell test sender - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    if (Send-SyslogMessage -Message $message -TargetIP $TargetIP -Port $Port -Facility $Facility -Severity $Severity -Source $Source) {
        $successCount++
    }

    if ($i -lt $Count) {
        Start-Sleep 1
    }
}

Write-Host ""
Write-Host "📊 Summary: $successCount/$Count messages sent successfully" -ForegroundColor $(if ($successCount -eq $Count) { "Green" } else { "Yellow" })

if ($successCount -gt 0) {
    Write-Host ""
    Write-Host "💡 Check your System Dashboard for these test messages in the syslog section." -ForegroundColor Cyan
    Write-Host "   Messages should appear with source '$Source' and facility '$Facility'." -ForegroundColor Gray
}

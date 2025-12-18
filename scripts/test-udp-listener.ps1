# Test UDP Listener
# Quick test to verify if we can bind to port 5514 for UDP syslog

param(
    [int]$Port = 5514,
    [int]$TestDurationSeconds = 30
)

Write-Host "🧪 Testing UDP Listener on Port $Port" -ForegroundColor Cyan
Write-Host "=" * 40

try {
    # Try to bind to the port
    $endpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $Port)
    $udpClient = [System.Net.Sockets.UdpClient]::new()
    $udpClient.Client.Bind($endpoint)
    $udpClient.Client.ReceiveTimeout = 1000

    Write-Host "✅ Successfully bound to UDP port $Port" -ForegroundColor Green
    Write-Host "🔊 Listening for messages for $TestDurationSeconds seconds..." -ForegroundColor Yellow
    Write-Host "   Send test messages using: .\scripts\test-syslog-sender.ps1" -ForegroundColor Gray
    Write-Host ""

    $messageCount = 0
    $endTime = (Get-Date).AddSeconds($TestDurationSeconds)

    while ((Get-Date) -lt $endTime) {
        try {
            $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
            $bytes = $udpClient.Receive([ref]$remote)
            if ($bytes.Length -gt 0) {
                $messageCount++
                $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                Write-Host "📨 Message $messageCount from $($remote.Address):$($remote.Port)" -ForegroundColor Green
                Write-Host "   $text" -ForegroundColor Gray
                Write-Host ""
            }
        }
        catch [System.Net.Sockets.SocketException] {
            if ($_.Exception.NativeErrorCode -ne 10060) {  # Not timeout
                Write-Host "⚠️ Socket error: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "❌ Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    $udpClient.Close()

    Write-Host "📊 Test completed: Received $messageCount messages" -ForegroundColor Cyan

    if ($messageCount -eq 0) {
        Write-Host "💡 No messages received. Try running: .\scripts\test-syslog-sender.ps1 -Port $Port" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "❌ Failed to bind to UDP port $Port" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "💡 Possible issues:" -ForegroundColor Yellow
    Write-Host "   • Port already in use by another process" -ForegroundColor Gray
    Write-Host "   • Firewall blocking the port" -ForegroundColor Gray
    Write-Host "   • Administrative privileges required" -ForegroundColor Gray
}

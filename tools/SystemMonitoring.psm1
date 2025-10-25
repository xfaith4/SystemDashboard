# System Dashboard Monitoring and Maintenance Module
# Provides health checks, maintenance tasks, and system monitoring

function Get-SystemDashboardHealth {
    Write-Host "🏥 System Dashboard Health Check" -ForegroundColor Cyan
    Write-Host "=" * 40

    $healthStatus = @{
        Database = $false
        WebInterface = $false
        TelemetryService = $false
        DataFlow = $false
        DiskSpace = $false
        Services = @{}
    }

    # 1. Database Health
    Write-Host "`n📊 Database Health:" -ForegroundColor White
    try {
        $dbResult = docker exec postgres-container psql -U sysdash_reader -d system_dashboard -t -c "SELECT NOW();"
        if ($dbResult) {
            Write-Host "  ✅ PostgreSQL: Connected and responsive" -ForegroundColor Green
            $healthStatus.Database = $true

            # Check data counts
            $counts = docker exec postgres-container psql -U sysdash_reader -d system_dashboard -t -c "
            SELECT
                'Windows Events: ' || COUNT(*)
            FROM telemetry.eventlog_windows_recent
            UNION ALL
            SELECT
                'IIS Requests: ' || COUNT(*)
            FROM telemetry.iis_requests_recent
            UNION ALL
            SELECT
                'Syslog Entries: ' || COUNT(*)
            FROM telemetry.syslog_recent;"

            Write-Host "  📈 Data Counts:" -ForegroundColor Gray
            $counts | ForEach-Object { Write-Host "    $($_.Trim())" -ForegroundColor Gray }
        }
    }
    catch {
        Write-Host "  ❌ Database: Connection failed - $($_.Exception.Message)" -ForegroundColor Red
    }

    # 2. Web Interface Health
    Write-Host "`n🌐 Web Interface Health:" -ForegroundColor White
    try {
        $webResponse = Invoke-WebRequest -Uri "http://localhost:5000/health" -UseBasicParsing -TimeoutSec 5
        if ($webResponse.StatusCode -eq 200) {
            Write-Host "  ✅ Flask Dashboard: Healthy (Status: $($webResponse.StatusCode))" -ForegroundColor Green
            $healthStatus.WebInterface = $true
        }
    }
    catch {
        Write-Host "  ❌ Flask Dashboard: Not responding" -ForegroundColor Red
    }

    # 3. Scheduled Task Health
    Write-Host "`n🔄 Scheduled Services Health:" -ForegroundColor White
    $tasks = @('SystemDashboard-Telemetry', 'SystemDashboard-WebUI')

    foreach ($taskName in $tasks) {
        try {
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($task) {
                $state = $task.State
                $icon = if ($state -eq 'Running') { '✅' } else { '⚠️' }
                Write-Host "  $icon $taskName`: $state" -ForegroundColor $(if ($state -eq 'Running') { 'Green' } else { 'Yellow' })
                $healthStatus.Services[$taskName] = ($state -eq 'Running')

                if ($state -eq 'Running') {
                    $healthStatus.TelemetryService = $true
                }
            }
            else {
                Write-Host "  ❌ $taskName`: Not found" -ForegroundColor Red
                $healthStatus.Services[$taskName] = $false
            }
        }
        catch {
            Write-Host "  ❌ $taskName`: Error checking status" -ForegroundColor Red
            $healthStatus.Services[$taskName] = $false
        }
    }

    # 4. Data Flow Health
    Write-Host "`n📈 Data Flow Health:" -ForegroundColor White
    try {
        $stagingFiles = Get-ChildItem -Path "./var/staging" -Filter "*.json" -ErrorAction SilentlyContinue
        $recentFiles = $stagingFiles | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-1) }

        if ($recentFiles.Count -gt 0) {
            Write-Host "  ✅ Data Staging: $($recentFiles.Count) files processed in last hour" -ForegroundColor Green
            $healthStatus.DataFlow = $true
        }
        else {
            Write-Host "  ⚠️ Data Staging: No recent activity" -ForegroundColor Yellow
        }

        # Check log files
        $logFiles = Get-ChildItem -Path "./var/log" -Filter "*.log" -ErrorAction SilentlyContinue
        $recentLogs = $logFiles | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-1) }

        Write-Host "  📝 Recent Log Activity: $($recentLogs.Count) log files updated" -ForegroundColor Gray
    }
    catch {
        Write-Host "  ❌ Data Flow: Cannot access staging/log directories" -ForegroundColor Red
    }

    # 5. Disk Space Health
    Write-Host "`n💾 Disk Space Health:" -ForegroundColor White
    try {
        $drive = Get-PSDrive -Name (Split-Path $PWD -Qualifier).Replace(':', '')
        $freeSpaceGB = [Math]::Round($drive.Free / 1GB, 2)
        $totalSpaceGB = [Math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
        $usedPercent = [Math]::Round(($drive.Used / ($drive.Used + $drive.Free)) * 100, 1)

        if ($freeSpaceGB -gt 1) {
            Write-Host "  ✅ Free Space: $freeSpaceGB GB available ($usedPercent% used)" -ForegroundColor Green
            $healthStatus.DiskSpace = $true
        }
        else {
            Write-Host "  ⚠️ Free Space: Only $freeSpaceGB GB available ($usedPercent% used)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ❌ Disk Space: Cannot determine free space" -ForegroundColor Red
    }

    # Overall Health Score
    Write-Host "`n🎯 Overall Health Score:" -ForegroundColor White
    $healthyComponents = @($healthStatus.Database, $healthStatus.WebInterface, $healthStatus.TelemetryService, $healthStatus.DataFlow, $healthStatus.DiskSpace) | Where-Object { $_ }
    $healthScore = [Math]::Round(($healthyComponents.Count / 5) * 100)

    $scoreColor = if ($healthScore -ge 80) { 'Green' } elseif ($healthScore -ge 60) { 'Yellow' } else { 'Red' }
    Write-Host "  🏆 System Health: $healthScore% ($($healthyComponents.Count)/5 components healthy)" -ForegroundColor $scoreColor

    return $healthStatus
}

function Invoke-MaintenanceTasks {
    Write-Host "🔧 System Dashboard Maintenance Tasks" -ForegroundColor Cyan
    Write-Host "=" * 40

    # 1. Clean old staging files
    Write-Host "`n🧹 Cleaning old staging files..." -ForegroundColor White
    try {
        $stagingDir = "./var/staging"
        $oldFiles = Get-ChildItem -Path $stagingDir -Filter "*.json" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }

        if ($oldFiles.Count -gt 0) {
            $oldFiles | Remove-Item -Force
            Write-Host "  ✅ Removed $($oldFiles.Count) old staging files" -ForegroundColor Green
        }
        else {
            Write-Host "  ℹ️ No old staging files to clean" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ❌ Error cleaning staging files: $($_.Exception.Message)" -ForegroundColor Red
    }

    # 2. Rotate log files
    Write-Host "`n📝 Managing log files..." -ForegroundColor White
    try {
        $logDir = "./var/log"
        $logFiles = Get-ChildItem -Path $logDir -Filter "*.log"

        foreach ($logFile in $logFiles) {
            if ($logFile.Length -gt 10MB) {
                $backupName = "$($logFile.BaseName)_$(Get-Date -Format 'yyyyMMdd').log"
                $backupPath = Join-Path $logDir $backupName

                Copy-Item $logFile.FullName $backupPath
                Clear-Content $logFile.FullName

                Write-Host "  ✅ Rotated large log file: $($logFile.Name)" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "  ❌ Error managing log files: $($_.Exception.Message)" -ForegroundColor Red
    }

    # 3. Database maintenance
    Write-Host "`n🗄️ Database maintenance..." -ForegroundColor White
    try {
        # Update table statistics
        docker exec postgres-container psql -U postgres -d system_dashboard -c "ANALYZE;"
        Write-Host "  ✅ Database statistics updated" -ForegroundColor Green

        # Check for old partitions
        $oldPartitions = docker exec postgres-container psql -U postgres -d system_dashboard -t -c "
        SELECT schemaname||'.'||tablename
        FROM pg_tables
        WHERE schemaname = 'telemetry'
        AND tablename ~ '_[0-9]{4}$'
        AND tablename < 'syslog_generic_' || to_char(current_date - interval '90 days', 'YYMM');"

        if ($oldPartitions -and $oldPartitions.Trim()) {
            Write-Host "  ⚠️ Found old partitions (>90 days): Consider cleanup" -ForegroundColor Yellow
        }
        else {
            Write-Host "  ✅ No old partitions requiring cleanup" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ❌ Error in database maintenance: $($_.Exception.Message)" -ForegroundColor Red
    }

    # 4. Service health check and restart if needed
    Write-Host "`n🔄 Service health verification..." -ForegroundColor White
    $tasks = @('SystemDashboard-Telemetry', 'SystemDashboard-WebUI')

    foreach ($taskName in $tasks) {
        try {
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($task -and $task.State -ne 'Running') {
                Start-ScheduledTask -TaskName $taskName
                Write-Host "  ✅ Restarted stopped task: $taskName" -ForegroundColor Green
                Start-Sleep 2
            }
            elseif ($task) {
                Write-Host "  ✅ Task running normally: $taskName" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "  ❌ Error checking task $taskName`: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n🎉 Maintenance tasks completed!" -ForegroundColor Green
}

function Start-HealthMonitoring {
    param(
        [int]$CheckIntervalMinutes = 15
    )

    Write-Host "🏥 Starting System Dashboard Health Monitoring" -ForegroundColor Cyan
    Write-Host "Check interval: $CheckIntervalMinutes minutes" -ForegroundColor Gray

    while ($true) {
        try {
            Write-Host "`n$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Health Check" -ForegroundColor Yellow
            $health = Get-SystemDashboardHealth

            # Alert on critical issues
            if (-not $health.Database) {
                Write-Host "🚨 ALERT: Database connection lost!" -ForegroundColor Red
            }

            if (-not $health.WebInterface) {
                Write-Host "🚨 ALERT: Web interface not responding!" -ForegroundColor Red
            }

            # Sleep until next check
            Start-Sleep -Seconds ($CheckIntervalMinutes * 60)
        }
        catch {
            Write-Host "Error in health monitoring: $($_.Exception.Message)" -ForegroundColor Red
            Start-Sleep -Seconds 300  # Wait 5 minutes before retry
        }
    }
}

Export-ModuleMember -Function Get-SystemDashboardHealth, Invoke-MaintenanceTasks, Start-HealthMonitoring

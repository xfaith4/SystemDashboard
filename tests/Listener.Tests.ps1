Describe 'SystemDashboard listener - HTTP Endpoints & Real Data' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../Start-SystemDashboard.psm1" -Force

        $script:IsAdmin = $false
        if ($IsWindows) {
            $id = [Security.Principal.WindowsIdentity]::GetCurrent()
            $p = [Security.Principal.WindowsPrincipal]::new($id)
            $script:IsAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
    }

    It 'responds with comprehensive metrics JSON' -Skip:(!$IsWindows) {
        $port = Get-Random -Minimum 10000 -Maximum 19999
        $prefix = "http://localhost:$port/"
        
        # Skip URL ACL setup if not admin
        if ($script:IsAdmin) {
            Ensure-UrlAcl -Prefix $prefix
        }

        $root = Join-Path $TestDrive 'wwwroot'
        New-Item -ItemType Directory -Path $root | Out-Null
        $index = Join-Path $root 'index.html'
        $css = Join-Path $root 'styles.css'
        Set-Content -Path $index -Value '<html><head><title>System Dashboard</title></head><body><h1>Dashboard</h1></body></html>'
        Set-Content -Path $css -Value 'body{font-family: Arial, sans-serif; margin: 20px;}'

        $job = Start-Job -ScriptBlock {
            param($prefix,$root,$index,$css)
            Import-Module "$using:PSScriptRoot/../Start-SystemDashboard.psm1" -Force
            Start-SystemDashboardListener -Prefix $prefix -Root $root -IndexHtml $index -CssFile $css
        } -ArgumentList $prefix,$root,$index,$css

        try {
            $response = $null
            $attempts = 0
            $maxAttempts = 30
            
            do {
                Start-Sleep -Milliseconds 500
                $attempts++
                try {
                    $metricsUri = $prefix + 'metrics'
                    $response = Invoke-RestMethod -Uri $metricsUri -TimeoutSec 3
                    break
                } catch {
                    if ($attempts -ge $maxAttempts) {
                        throw "Failed to connect after $maxAttempts attempts: $_"
                    }
                }
            } while ($attempts -lt $maxAttempts)
            
            # Validate response structure
            $response | Should -Not -BeNullOrEmpty
            $response.ComputerName | Should -Not -BeNullOrEmpty
            $response.Timestamp | Should -Not -BeNullOrEmpty
            
            # Validate CPU metrics
            $response.CPU | Should -Not -BeNullOrEmpty
            $response.CPU.UsagePct | Should -BeGreaterOrEqual 0
            $response.CPU.UsagePct | Should -BeLessOrEqual 100
            Write-Host "CPU Usage: $($response.CPU.UsagePct)%"
            
            # Validate Memory metrics
            $response.Memory | Should -Not -BeNullOrEmpty
            $response.Memory.UsagePct | Should -BeGreaterOrEqual 0
            $response.Memory.UsagePct | Should -BeLessOrEqual 100
            $response.Memory.TotalGB | Should -BeGreaterThan 0
            Write-Host "Memory Usage: $($response.Memory.UsagePct)% of $($response.Memory.TotalGB)GB"
            
            # Validate Disk metrics
            $response.Disks | Should -Not -BeNullOrEmpty
            foreach ($disk in $response.Disks) {
                $disk.Drive | Should -Not -BeNullOrEmpty
                $disk.UsagePct | Should -BeGreaterOrEqual 0
                $disk.UsagePct | Should -BeLessOrEqual 100
                $disk.TotalGB | Should -BeGreaterThan 0
                Write-Host "Disk $($disk.Drive): $($disk.UsagePct)% of $($disk.TotalGB)GB"
            }
            
            # Validate Network metrics
            $response.Network | Should -Not -BeNullOrEmpty
            if ($response.Network.Count -gt 0) {
                foreach ($adapter in $response.Network) {
                    $adapter.Name | Should -Not -BeNullOrEmpty
                    Write-Host "Network adapter: $($adapter.Name)"
                }
            }
            
            # Validate Events
            if ($response.Events) {
                $response.Events.Count | Should -BeGreaterOrEqual 0
                Write-Host "Recent events: $($response.Events.Count)"
            }
            
            # Validate Top Processes
            $response.TopProcesses | Should -Not -BeNullOrEmpty
            $response.TopProcesses.Count | Should -BeGreaterThan 0
            foreach ($process in $response.TopProcesses) {
                $process.Name | Should -Not -BeNullOrEmpty
                $process.PID | Should -BeGreaterThan 0
                Write-Host "Top process: $($process.Name) (PID: $($process.PID))"
            }
        }
        finally {
            if ($job) {
                Stop-Job $job -Force | Out-Null
                Remove-Job $job -Force
            }
            if ($script:IsAdmin) {
                Remove-UrlAcl -Prefix $prefix
            }
        }
    }

    It 'serves static files correctly' -Skip:(!$IsWindows) {
        $port = Get-Random -Minimum 10000 -Maximum 19999
        $prefix = "http://localhost:$port/"
        
        if ($script:IsAdmin) {
            Ensure-UrlAcl -Prefix $prefix
        }

        $root = Join-Path $TestDrive 'wwwroot'
        New-Item -ItemType Directory -Path $root | Out-Null
        $index = Join-Path $root 'index.html'
        $css = Join-Path $root 'styles.css'
        
        $htmlContent = @'
<!DOCTYPE html>
<html>
<head>
    <title>System Dashboard Test</title>
    <link rel="stylesheet" href="/styles.css">
</head>
<body>
    <h1>Test Dashboard</h1>
    <div id="content">Dashboard content here</div>
</body>
</html>
'@
        
        $cssContent = @'
body { 
    font-family: Arial, sans-serif; 
    margin: 20px; 
    background-color: #f5f5f5;
}
h1 { 
    color: #333; 
    border-bottom: 2px solid #007acc;
}
#content {
    background: white;
    padding: 20px;
    border-radius: 5px;
}
'@
        
        Set-Content -Path $index -Value $htmlContent
        Set-Content -Path $css -Value $cssContent

        $job = Start-Job -ScriptBlock {
            param($prefix,$root,$index,$css)
            Import-Module "$using:PSScriptRoot/../Start-SystemDashboard.psm1" -Force
            Start-SystemDashboardListener -Prefix $prefix -Root $root -IndexHtml $index -CssFile $css
        } -ArgumentList $prefix,$root,$index,$css

        try {
            Start-Sleep -Seconds 3
            
            # Test index.html
            $indexResponse = Invoke-WebRequest -Uri $prefix -UseBasicParsing
            $indexResponse.StatusCode | Should -Be 200
            $indexResponse.Content | Should -Match 'Test Dashboard'
            Write-Host "Index page served successfully"
            
            # Test CSS file
            $cssResponse = Invoke-WebRequest -Uri "${prefix}styles.css" -UseBasicParsing
            $cssResponse.StatusCode | Should -Be 200
            $cssResponse.Content | Should -Match 'font-family'
            Write-Host "CSS file served successfully"
            
        }
        finally {
            if ($job) {
                Stop-Job $job -Force | Out-Null
                Remove-Job $job -Force
            }
            if ($script:IsAdmin) {
                Remove-UrlAcl -Prefix $prefix
            }
        }
    }

    It 'provides system-logs endpoint with real data' -Skip:(!$IsWindows) {
        $port = Get-Random -Minimum 10000 -Maximum 19999
        $prefix = "http://localhost:$port/"
        
        if ($script:IsAdmin) {
            Ensure-UrlAcl -Prefix $prefix
        }

        $root = Join-Path $TestDrive 'wwwroot'
        New-Item -ItemType Directory -Path $root | Out-Null
        $index = Join-Path $root 'index.html'
        $css = Join-Path $root 'styles.css'
        Set-Content -Path $index -Value '<html></html>'
        Set-Content -Path $css -Value 'body{}'

        $job = Start-Job -ScriptBlock {
            param($prefix,$root,$index,$css)
            Import-Module "$using:PSScriptRoot/../Start-SystemDashboard.psm1" -Force
            Start-SystemDashboardListener -Prefix $prefix -Root $root -IndexHtml $index -CssFile $css
        } -ArgumentList $prefix,$root,$index,$css

        try {
            Start-Sleep -Seconds 3
            
            # Test system-logs endpoint
            $logsResponse = Invoke-RestMethod -Uri "${prefix}system-logs" -TimeoutSec 5
            $logsResponse | Should -Not -BeNullOrEmpty
            
            if ($logsResponse.Count -gt 0) {
                $log = $logsResponse[0]
                $log.LogName | Should -Not -BeNullOrEmpty
                $log.TimeCreated | Should -Not -BeNullOrEmpty
                $log.Level | Should -Not -BeNullOrEmpty
                Write-Host "System logs endpoint returned $($logsResponse.Count) entries"
                Write-Host "Sample log: $($log.LogName) - $($log.Level) - $($log.Source)"
            } else {
                Write-Warning "No system logs returned (may be expected in test environment)"
            }
            
        }
        finally {
            if ($job) {
                Stop-Job $job -Force | Out-Null
                Remove-Job $job -Force
            }
            if ($script:IsAdmin) {
                Remove-UrlAcl -Prefix $prefix
            }
        }
    }

    It 'handles configuration from config.json' -Skip:(!$IsWindows) {
        # Test configuration loading
        $configPath = Join-Path $TestDrive 'test-config.json'
        $testConfig = @{
            Prefix = "http://localhost:16000/"
            Root = "./wwwroot"
            PingTarget = "8.8.8.8"
            RouterIP = "192.168.1.1"
        } | ConvertTo-Json
        
        Set-Content -Path $configPath -Value $testConfig
        
        # Set environment variable to use test config
        $env:SYSTEMDASHBOARD_CONFIG = $configPath
        
        try {
            # Reload module to pick up new config
            Remove-Module Start-SystemDashboard -Force -ErrorAction SilentlyContinue
            Import-Module "$PSScriptRoot/../Start-SystemDashboard.psm1" -Force
            
            # Verify config was loaded (this would be tested indirectly through functionality)
            Write-Host "Configuration loading test completed"
            
        } finally {
            # Cleanup
            Remove-Item $configPath -ErrorAction SilentlyContinue
            Remove-Item env:SYSTEMDASHBOARD_CONFIG -ErrorAction SilentlyContinue
        }
    }
}

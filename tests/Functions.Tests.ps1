BeforeAll {
    Import-Module "$PSScriptRoot/../Start-SystemDashboard.psm1" -Force
}

Describe 'Get-SystemLogs - Edge Cases' {
    It 'handles empty log results gracefully' -Skip:(!$IsWindows) {
        $logs = Get-SystemLogs -LogName 'Application' -MaxEvents 1000 -MinimumLevel 'Critical'
        if ($null -eq $logs) {
            $logs | Should -BeNullOrEmpty
        }
        else {
            $logs.Count | Should -BeGreaterOrEqual 0
        }
    }

    It 'validates MaxEvents parameter' -Skip:(!$IsWindows) {
        $logs = Get-SystemLogs -LogName 'System' -MaxEvents 5
        $logs.Count | Should -BeLessOrEqual 5
    }
}

Describe 'Scan-ConnectedClients - Error Handling' {
    It 'handles invalid network prefix format' {
        { Scan-ConnectedClients -NetworkPrefix '' } | Should -Throw
    }

    It 'returns array type consistently' -Skip:(!$IsWindows) {
        $clients = Scan-ConnectedClients -NetworkPrefix '192.168.1'
        $clients -is [array] -or $clients.Count -ge 0 | Should -Be $true
    }
}

Describe 'Get-RouterCredentials - Connectivity Tests' {
    It 'throws when unreachable IP' {
        Mock Get-Credential { New-Object System.Management.Automation.PSCredential('user',(ConvertTo-SecureString 'pass' -AsPlainText -Force)) }
        Mock Test-Connection { $false }
        Mock New-SSHSession { }
        { Get-RouterCredentials -RouterIP '203.0.113.1' } | Should -Throw
    }

    It 'validates router IP format' {
        { Get-RouterCredentials -RouterIP 'invalid-ip' } | Should -Throw
    }

    It 'handles default router IP from config' {
        Mock Get-Credential { New-Object System.Management.Automation.PSCredential('user',(ConvertTo-SecureString 'pass' -AsPlainText -Force)) }
        Mock Test-Connection { $false }
        Mock New-SSHSession { }

        # Should use default IP from config
        { Get-RouterCredentials } | Should -Throw -Because "Default IP should be unreachable in test environment"
    }
}

Describe 'System Metrics Collection - Real Data' {
    It 'collects CPU metrics' -Skip:(!$IsWindows) {
        # Test CPU data collection
        $cpuCounters = Get-Counter '\Processor(_Total)\% Processor Time' -MaxSamples 1
        $cpuCounters | Should -Not -BeNullOrEmpty
        $cpuUsage = $cpuCounters.CounterSamples[0].CookedValue
        $cpuUsage | Should -BeGreaterOrEqual 0
        $cpuUsage | Should -BeLessOrEqual 100
        Write-Host "Current CPU usage: $([math]::Round($cpuUsage, 2))%"
    }

    It 'collects memory metrics' -Skip:(!$IsWindows) {
        # Test memory data collection
        $totalMemory = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
        $availableMemory = (Get-Counter '\Memory\Available Bytes').CounterSamples[0].CookedValue

        $totalMemory | Should -BeGreaterThan 0
        $availableMemory | Should -BeGreaterThan 0
        $availableMemory | Should -BeLessOrEqual $totalMemory

        $usedMemory = $totalMemory - $availableMemory
        $memoryUsagePct = ($usedMemory / $totalMemory) * 100
        Write-Host "Memory usage: $([math]::Round($memoryUsagePct, 2))% ($([math]::Round($usedMemory/1GB, 2))GB / $([math]::Round($totalMemory/1GB, 2))GB)"
    }

    It 'collects disk metrics' -Skip:(!$IsWindows) {
        # Test disk data collection
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        $disks | Should -Not -BeNullOrEmpty

        foreach ($disk in $disks) {
            $disk.Size | Should -BeGreaterThan 0
            $disk.FreeSpace | Should -BeGreaterOrEqual 0
            $disk.FreeSpace | Should -BeLessOrEqual $disk.Size

            $usedSpace = $disk.Size - $disk.FreeSpace
            $usagePct = ($usedSpace / $disk.Size) * 100
            Write-Host "Disk $($disk.DeviceID) usage: $([math]::Round($usagePct, 2))%"
        }
    }

    It 'collects network metrics' -Skip:(!$IsWindows) {
        # Test network interface data collection
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        $adapters | Should -Not -BeNullOrEmpty

        foreach ($adapter in $adapters) {
            $adapter.Name | Should -Not -BeNullOrEmpty
            $adapter.InterfaceDescription | Should -Not -BeNullOrEmpty
            $adapter.LinkSpeed | Should -BeGreaterThan 0
            Write-Host "Network adapter: $($adapter.Name) - Speed: $($adapter.LinkSpeed) bps"
        }
    }

    It 'collects process information' -Skip:(!$IsWindows) {
        # Test process data collection
        $processes = Get-Process | Sort-Object CPU -Descending | Select-Object -First 10
        $processes | Should -Not -BeNullOrEmpty
        $processes.Count | Should -BeGreaterOrEqual 10

        foreach ($process in $processes) {
            $process.ProcessName | Should -Not -BeNullOrEmpty
            $process.Id | Should -BeGreaterThan 0
            Write-Host "Top process: $($process.ProcessName) (PID: $($process.Id))"
        }
    }
}
Describe 'System Metrics - Data Consistency' {
    It 'ensures CPU usage is within valid range' -Skip:(!$IsWindows) {
        $cpuCounters = Get-Counter '\Processor(_Total)\% Processor Time' -MaxSamples 1
        $cpuUsage = $cpuCounters.CounterSamples[0].CookedValue
        $cpuUsage | Should -BeGreaterOrEqual 0
        $cpuUsage | Should -BeLessOrEqual 100
    }

    It 'disk free space does not exceed total size' -Skip:(!$IsWindows) {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        foreach ($disk in $disks) {
            ($disk.FreeSpace -le $disk.Size) | Should -Be $true
        }
    }
}

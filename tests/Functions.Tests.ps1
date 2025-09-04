BeforeAll {
    . "$PSScriptRoot/../Start-SystemDashboard.ps1"
}

Describe 'Get-SystemLogs' {
    It 'handles filter level' -Skip:(!$IsWindows) {
        $logs = Get-SystemLogs -LogName 'Application' -MaxEvents 5 -MinimumLevel 'Error'
        $logs | ForEach-Object { $_.Level | Should -Match 'Error|Critical' }
    }
}

Describe 'Scan-ConnectedClients' {
    It 'returns empty when no neighbors' -Skip:(!$IsWindows) {
        Mock Get-NetNeighbor { @() }
        (Scan-ConnectedClients -NetworkPrefix '192.168.1') | Should -BeEmpty
    }
}

Describe 'Get-RouterCredentials' {
    It 'throws when unreachable' {
        Mock Get-Credential { New-Object System.Management.Automation.PSCredential('user',(ConvertTo-SecureString 'pass' -AsPlainText -Force)) }
        Mock Test-Connection { $false }
        Mock New-SSHSession { }
        { Get-RouterCredentials -RouterIP '203.0.113.1' } | Should -Throw
    }
}

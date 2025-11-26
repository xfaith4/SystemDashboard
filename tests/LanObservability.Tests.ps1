BeforeAll {
    Import-Module "$PSScriptRoot/../tools/LanObservability.psm1" -Force
}

Describe 'LanObservability - Null Safety Tests' {
    Context 'Invoke-RouterClientPoll' {
        It 'returns an array when password is not configured' {
            $config = @{
                Service = @{
                    Asus = @{
                        Uri = 'http://192.168.1.1'
                        Username = 'test'
                        SSH = @{
                            Enabled = $false
                        }
                    }
                }
            }
            
            # Clear environment variable to simulate no password
            $oldEnv = $env:ASUS_ROUTER_PASSWORD
            $env:ASUS_ROUTER_PASSWORD = $null
            
            try {
                $result = Invoke-RouterClientPoll -Config $config -WarningAction SilentlyContinue
                
                # Should return an empty array, not null
                $result | Should -Not -BeNullOrEmpty
                $result | Should -BeOfType [Array]
                $result.Count | Should -Be 0
            }
            finally {
                $env:ASUS_ROUTER_PASSWORD = $oldEnv
            }
        }
        
        It 'returns an array when router connection fails' {
            $config = @{
                Service = @{
                    Asus = @{
                        Uri = 'http://192.168.254.254'  # Unreachable IP
                        Username = 'test'
                        PasswordSecret = $null
                        SSH = @{
                            Enabled = $false
                        }
                    }
                }
            }
            
            $env:ASUS_ROUTER_PASSWORD = 'test'
            
            try {
                $result = Invoke-RouterClientPoll -Config $config -WarningAction SilentlyContinue
                
                # Even on connection failure, should return an array
                $result | Should -Not -BeNullOrEmpty
                $result | Should -BeOfType [Array]
                $result.Count | Should -Be 0
            }
            finally {
                $env:ASUS_ROUTER_PASSWORD = $null
            }
        }
    }
    
    Context 'Invoke-LanDeviceCollection' {
        It 'handles empty client list without throwing Count error' {
            $config = @{
                Service = @{
                    Asus = @{
                        Uri = 'http://192.168.1.1'
                        Username = 'test'
                        SSH = @{
                            Enabled = $false
                        }
                    }
                }
            }
            
            # Mock connection
            $mockConnection = New-MockObject -Type System.Data.SQLite.SQLiteConnection
            
            # Mock Invoke-RouterClientPoll to return empty array
            Mock Invoke-RouterClientPoll { @() } -ModuleName LanObservability
            
            # Should not throw an error about Count property
            { Invoke-LanDeviceCollection -Config $config -DbConnection $mockConnection -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }
}

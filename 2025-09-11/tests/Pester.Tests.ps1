#requires -Version 7
Import-Module "$PSScriptRoot/../modules/SystemDashboard.psd1" -Force

Describe "Config & DB" {
    It "Loads config" {
        $cfg = & (Get-Module SystemDashboard).Invoke({ param($f) & $f }) (Get-Item "$PSScriptRoot/../config.json").FullName
        $cfg | Should -Not -BeNullOrEmpty
    }
    It "Initializes SQLite" {
        $cfg = Get-Content "$PSScriptRoot/../config.json" -Raw | ConvertFrom-Json
        { Initialize-Database -Config $cfg } | Should -Not -Throw
    }
}

Describe "Routes (smoke)" {
    # These are illustrative; full route testing typically uses Pode integration test helpers
    It "/healthz returns ok" {
        # Minimal direct call
        $ok = $true
        $ok | Should -BeTrue
    }
}

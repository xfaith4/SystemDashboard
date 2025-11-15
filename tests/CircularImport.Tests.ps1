Describe 'Circular Import Fix Validation' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    }
    
    It 'module can be imported without circular reference error' {
        # This should not throw "module nesting limit exceeded"
        { Import-Module "$script:RepoRoot/Start-SystemDashboard.psm1" -Force -ErrorAction Stop } | Should -Not -Throw
        
        # Verify module is loaded
        $module = Get-Module -Name 'Start-SystemDashboard'
        $module | Should -Not -BeNullOrEmpty
        $module.Name | Should -Be 'Start-SystemDashboard'
    }
    
    It 'Start-SystemDashboard.ps1 script can be dot-sourced without circular reference' {
        # Remove any existing module first
        Remove-Module -Name 'Start-SystemDashboard' -ErrorAction SilentlyContinue
        
        # Dot-source the script - should not throw
        { . "$script:RepoRoot/Start-SystemDashboard.ps1" } | Should -Not -Throw
        
        # Verify module is loaded after script execution
        $module = Get-Module -Name 'Start-SystemDashboard'
        $module | Should -Not -BeNullOrEmpty
    }
    
    It 'multiple imports of Start-SystemDashboard.ps1 are prevented by guard' {
        # Remove any existing module first
        Remove-Module -Name 'Start-SystemDashboard' -ErrorAction SilentlyContinue
        
        # First import
        . "$script:RepoRoot/Start-SystemDashboard.ps1"
        $firstModule = Get-Module -Name 'Start-SystemDashboard'
        
        # Second import (should be guarded)
        . "$script:RepoRoot/Start-SystemDashboard.ps1"
        $secondModule = Get-Module -Name 'Start-SystemDashboard'
        
        # Should be the same module instance
        $secondModule | Should -Not -BeNullOrEmpty
        $secondModule.Path | Should -Be $firstModule.Path
    }
    
    It 'exported functions are available after import' {
        Remove-Module -Name 'Start-SystemDashboard' -ErrorAction SilentlyContinue
        Import-Module "$script:RepoRoot/Start-SystemDashboard.psm1" -Force
        
        # Check for key exported functions
        $expectedFunctions = @(
            'Start-SystemDashboardListener',
            'Start-SystemDashboard',
            'Get-SystemLogs',
            'Get-MockSystemMetrics'
        )
        
        foreach ($funcName in $expectedFunctions) {
            Get-Command -Name $funcName -Module 'Start-SystemDashboard' -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
    
    It 'module does not import itself internally' {
        # Read the module file content
        $moduleContent = Get-Content "$script:RepoRoot/Start-SystemDashboard.psm1" -Raw
        
        # The module should NOT contain an Import-Module line that imports itself
        # Look for patterns like "Import-Module (Join-Path $PSScriptRoot 'Start-SystemDashboard.psm1')"
        $moduleContent | Should -Not -Match 'Import-Module.*Start-SystemDashboard\.psm1'
    }
    
    AfterAll {
        # Cleanup
        Remove-Module -Name 'Start-SystemDashboard' -ErrorAction SilentlyContinue
    }
}

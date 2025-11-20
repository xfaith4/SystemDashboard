<#
Pester tests for NetworkClientScan.ps1
- Pure static checks; never executes the scanner logic.
- Validates parsing, cross-version compatibility, and our house rules.

How to run:
Install-Module Pester -Scope CurrentUser -Force
Invoke-Pester -Path "$PSScriptRoot" -Output Detailed
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Locate the script under test ------------------------------------------
$ScriptUnderTest = Join-Path $PSScriptRoot '.\NetworkClientScan.ps1' | Resolve-Path
$Content         = Get-Content -LiteralPath $ScriptUnderTest -Raw
# ---------------------------------------------------------------------------
It 'Does not place a colon immediately after a variable in strings (use $() or -f)' {
    # Heuristic: looks for "$Word:" which can trigger the scope parser.
    # Allow known scopes like $env:, $global:, $script:, $private:
    $Content -match '(?<!\$)(\$\w+:)' | Out-Null
    $matches = [regex]::Matches($Content, '(?<!\$)(\$\w+:)')
    $bad = @()
    foreach ($m in $matches) {
        $val = $m.Groups[1].Value
        if ($val -notmatch '^\$(env|global|script|private):') { $bad += $val }
    }
    $bad.Count | Should -Be 0 -Because ("Found suspicious variable+colon: {0}" -f ($bad -join ', '))
}
# ------------------- Extract functions for static analysis -------------------
# We want to parse the script without executing it, so we extract the functions

# --- Helper: parse in a given engine without executing the file ------------
function Test-ParseInEngine {
    param(
        [Parameter(Mandatory)][string]$EnginePath
    )
    if (-not (Test-Path $EnginePath)) { return $false }

    # Use a tiny wrapper that just compiles the text into a scriptblock
    $cmd = @"
& {
  \$ErrorActionPreference = 'Stop'
  [void][ScriptBlock]::Create([IO.File]::ReadAllText('$($ScriptUnderTest.ToString().Replace("'","''"))'))
}
"@
    # Start the engine with -Command and return success/failure
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $EnginePath
    $psi.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -Command -'
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi | ForEach-Object { $_ }
    [void]$p.Start()
    $p.StandardInput.WriteLine($cmd)
    $p.StandardInput.Close()
    $null = $p.StandardOutput.ReadToEnd()
    $err  = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($p.ExitCode -ne 0) {
        # Replace the failing Write-Host with this safer version:
        Write-Host ("Parse failed in {0}:{1}{2}" -f $EnginePath, [Environment]::NewLine, $err) -ForegroundColor Red


        return $false
    }
    return $true
}

# --- Discover PowerShell engines (best effort) ------------------------------
$PS5Path  = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$PS7Path  = (Get-Command pwsh -ErrorAction SilentlyContinue).Path

# --- TESTS ------------------------------------------------------------------
Describe 'NetworkClientScan.ps1 - Static and Parse Checks' {

    Context 'Basic hygiene' {
        It 'File exists' {
            Test-Path $ScriptUnderTest | Should -BeTrue
        }

        It 'Parses on the current host engine' {
            # Compile current content into a scriptblock (no execution)
            { [void][ScriptBlock]::Create($Content) } | Should -Not -Throw
        }

        It 'Contains Set-StrictMode and sets $ErrorActionPreference' {
            $Content | Should -Match 'Set-StrictMode\s*-Version\s+Latest'
            $Content | Should -Match '\$ErrorActionPreference\s*=\s*''Stop'''
        }
    }

    Context 'Cross-version parsing' {
        It 'Parses in Windows PowerShell 5.1 (if available)' -Skip:(-not (Test-Path $PS5Path)) {
            Test-ParseInEngine -EnginePath $PS5Path | Should -BeTrue
        }

        It 'Parses in PowerShell 7+ (if available)' -Skip:([string]::IsNullOrWhiteSpace($PS7Path)) {
            Test-ParseInEngine -EnginePath $PS7Path | Should -BeTrue
        }
    }

    Context 'House rules: parallel + using and exports' {
        It 'Does NOT contain $using: (PS 5.1 parser gotcha)' {
            $Content | Should -Not -Match '\$using\s*:'
        }

        It 'If using -Parallel, it emits results (no shared-state Add())' {
            # Look for a simple pattern: -Parallel block that outputs $_ or an IP string
            # This is heuristic but catches the style we prefer.
            $usesParallel = $Content -match '-Parallel\s*\{'
            if ($usesParallel) {
                # Ensure it "emits" something (the pipeline/$_) inside the block
                ($Content -match '-Parallel\s*\{[^}]*\b(\$_|\bWrite-Output\b|^ {0,}\S+)$') | Should -BeTrue
            } else {
                # If no -Parallel at all, that's also acceptable
                $true | Should -BeTrue
            }
        }

        It 'Has ImportExcel guard (Get-Module -ListAvailable -Name ImportExcel) before Export-Excel' {
            $hasGuard     = $Content -match 'Get-Module\s+-ListAvailable\s+-Name\s+ImportExcel'
            $callsExportX = $Content -match '\bExport-Excel\b'
            if ($callsExportX) {
                $hasGuard | Should -BeTrue
            } else {
                # If not using Export-Excel at all, it must export CSV
                $Content | Should -Match '\bExport-Csv\b'
            }
        }

        It 'Provides CSV fallback' {
            $Content | Should -Match '\bExport-Csv\b'
        }

        It 'Does not contain hard-coded test export paths (e.g., C:\\temp\\test.xlsx)' {
            $Content | Should -Not -Match '(?i)c:\\\\temp\\\\test\.xlsx'
        }
    }
}

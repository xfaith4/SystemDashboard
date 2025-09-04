Describe 'SystemDashboard listener' {
    BeforeAll {
        . "$PSScriptRoot/../Start-SystemDashboard.ps1"

        $script:IsAdmin = $false
        if ($IsWindows) {
            $id = [Security.Principal.WindowsIdentity]::GetCurrent()
            $p = [Security.Principal.WindowsPrincipal]::new($id)
            $script:IsAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
    }

    It 'responds with metrics JSON' -Skip:(!$IsWindows -or -not $IsAdmin) {

    }

    It 'responds with metrics JSON' -Skip:(!$IsWindows) {

        $port = Get-Random -Minimum 10000 -Maximum 19999
        $prefix = "http://localhost:$port/"
        Ensure-UrlAcl -Prefix $prefix

        $root = Join-Path $TestDrive 'wwwroot'
        New-Item -ItemType Directory -Path $root | Out-Null
        $index = Join-Path $root 'index.html'
        $css = Join-Path $root 'styles.css'
        Set-Content -Path $index -Value '<html></html>'
        Set-Content -Path $css -Value 'body{}'

        $job = Start-Job -ScriptBlock {
            param($prefix,$root,$index,$css)
            Start-SystemDashboardListener -Prefix $prefix -Root $root -IndexHtml $index -CssFile $css
        } -ArgumentList $prefix,$root,$index,$css

        try {
            $response = $null
            for ($i=0; $i -lt 20; $i++) {
                Start-Sleep -Milliseconds 200
                try {

                    $metricsUri = $prefix + 'metrics'
                    $response = Invoke-RestMethod -Uri $metricsUri -TimeoutSec 2

                    $response = Invoke-RestMethod -Uri "$prefix/metrics" -TimeoutSec 2

                    break
                } catch {}
            }
            $response | Should -Not -BeNullOrEmpty
            $response.ComputerName | Should -Not -BeNullOrEmpty
        }
        finally {
            Stop-Job $job -Force | Out-Null
            Remove-Job $job
            Remove-UrlAcl -Prefix $prefix
        }
    }
}

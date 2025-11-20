# 1. Stop any running PromLens
Get-Process promlens -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. Remove the old promlens directory
Remove-Item -Recurse -Force "G:\Storage\BenStuff\Development\Observability\promlens" -ErrorAction SilentlyContinue

# 3. Re-create the directory
New-Item -ItemType Directory -Path "G:\Storage\BenStuff\Development\Observability\promlens" -Force | Out-Null

# 4. Download the latest Windows build (AMD64)
if (!(Test-Path "G:\Storage\BenStuff\Development\Observability\promlens\promlens.exe")) {
    $outZip = "G:\Storage\BenStuff\Development\Observability\promlens\promlens.zip"
    $downloaded = $false
    try {
        $apiUrl = "https://api.github.com/repos/prometheus/promlens/releases/latest"
        $headers = @{ 'User-Agent' = 'PowerShell'; 'Accept' = 'application/vnd.github+json' }
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers
        $asset = $null
        if ($release -and $release.assets) {
            $asset = $release.assets | Where-Object {
                $_.name -match "windows" -and ($_.name -match "amd64" -or $_.name -match "x86_64") -and $_.name -match "\.zip$"
            } | Select-Object -First 1
        }
        if ($asset -and $asset.browser_download_url) {
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $outZip -UseBasicParsing
            $downloaded = $true
        }
    } catch {
        Write-Warning "Failed to query GitHub API for latest release (prometheus/promlens): $($_.Exception.Message)"
    }

    if (-not $downloaded) {
        try {
            $apiUrl2 = "https://api.github.com/repos/promlabs/promlens/releases/latest"
            $headers2 = @{ 'User-Agent' = 'PowerShell'; 'Accept' = 'application/vnd.github+json' }
            $release2 = Invoke-RestMethod -Uri $apiUrl2 -Headers $headers2
            $asset2 = $null
            if ($release2 -and $release2.assets) {
                $asset2 = $release2.assets | Where-Object {
                    $_.name -match "windows" -and ($_.name -match "amd64" -or $_.name -match "x86_64") -and $_.name -match "\.zip$"
                } | Select-Object -First 1
            }
            if ($asset2 -and $asset2.browser_download_url) {
                Invoke-WebRequest -Uri $asset2.browser_download_url -OutFile $outZip -UseBasicParsing
                $downloaded = $true
            }
        } catch {
            Write-Warning "Failed to query GitHub API for latest release (promlabs/promlens): $($_.Exception.Message)"
        }
    }

    if (-not $downloaded) {
        $fallbackUrlCandidates = @(
            "https://github.com/prometheus/promlens/releases/latest/download/promlens-windows-amd64.zip",
            "https://github.com/prometheus/promlens/releases/latest/download/promlens-windows-x86_64.zip"
        )
        foreach ($url in $fallbackUrlCandidates) {
            try {
                Invoke-WebRequest -Uri $url -OutFile $outZip -UseBasicParsing
                $downloaded = $true
                break
            } catch {
                Write-Warning "Download failed from ${url}: $($_.Exception.Message)"
            }
        }
    }

    if ($downloaded -and (Test-Path $outZip)) {
        # 5. Unzip into the promlens folder
        Expand-Archive -Path $outZip -DestinationPath "G:\Storage\BenStuff\Development\Observability\promlens" -Force

        # 6. Clean up
        Remove-Item $outZip -ErrorAction SilentlyContinue

        $exeCandidate = Get-ChildItem -Path "G:\Storage\BenStuff\Development\Observability\promlens" -Recurse -Filter promlens.exe | Select-Object -First 1
        if ($exeCandidate -and $exeCandidate.FullName -ne "G:\Storage\BenStuff\Development\Observability\promlens\promlens.exe") {
            Move-Item -Force $exeCandidate.FullName "G:\Storage\BenStuff\Development\Observability\promlens\promlens.exe"
        }
    } else {
        Write-Error "Failed to download PromLens release asset."
    }
} else {
    Write-Host "promlens.exe already present; skipping download and unzip"
}

# 7. Confirm the binary is in place
Test-Path "G:\Storage\BenStuff\Development\Observability\promlens\promlens.exe"

# (Requires Go 1.18+ in your PATH)

$installDir = "G:\Storage\BenStuff\Development\Observability\promlens"
$pathParts = ($env:Path -split ';')
if (-not ($pathParts | Where-Object { $_ -ieq $installDir })) {
    setx PATH ($env:Path.TrimEnd(';') + ";" + $installDir) | Out-Null
    $env:Path = $env:Path.TrimEnd(';') + ";" + $installDir
}
$exePath = Join-Path $installDir "promlens.exe"

# Make sure $GOPATH/bin (or $GOBIN) is in your PATH, then:
if (Test-Path $exePath) { & $exePath --version } else { Write-Error "promlens.exe not found after installation." }


function Get-SystemDashboardRoot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]
        $FallbackPath = $PSScriptRoot
    )

    if ($env:SYSTEMDASHBOARD_ROOT) {
        try {
            return (Get-Item -LiteralPath $env:SYSTEMDASHBOARD_ROOT -ErrorAction Stop).FullName
        } catch {
            # Fall through to fallback detection when environment variable points to a non-existent directory
        }
    }

    $candidatePath = $FallbackPath
    if (-not (Test-Path -LiteralPath $candidatePath)) {
        $candidatePath = Split-Path -Parent $candidatePath
    }

    while ($candidatePath) {
        if (Test-Path -LiteralPath (Join-Path $candidatePath 'config.json')) {
            return (Get-Item -LiteralPath $candidatePath).FullName
        }

        $parent = Split-Path -Parent $candidatePath
        if ($parent -and ($parent -ne $candidatePath)) {
            $candidatePath = $parent
            continue
        }

        break
    }

    return (Get-Item -LiteralPath $candidatePath).FullName
}

function Get-WebUIPortFilePath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]
        $RootPath = (Get-SystemDashboardRoot)
    )

    return Join-Path $RootPath 'var\webui-port.txt'
}

function Read-WebUIPortFromFile {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]
        $DefaultPort = 5000,
        [Parameter()]
        [string]
        $PortFilePath = (Get-WebUIPortFilePath)
    )

    if (Test-Path -LiteralPath $PortFilePath) {
        $raw = (Get-Content -LiteralPath $PortFilePath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        if ([int]::TryParse($raw, [ref]$parsed) -and $parsed -ge 1024 -and $parsed -le 65535) {
            return $parsed
        }
    }

    return $DefaultPort
}

function Write-WebUIPortToFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]
        $Port,
        [Parameter()]
        [string]
        $PortFilePath = (Get-WebUIPortFilePath)
    )

    $directory = Split-Path -Parent $PortFilePath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $Port.ToString() | Set-Content -LiteralPath $PortFilePath -Encoding ASCII
}

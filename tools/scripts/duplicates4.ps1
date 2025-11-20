function Sync-Files {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Begin {
        $startTime = Get-Date
        $logPath = Join-Path $DestinationPath "SyncLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    }

    Process {
        try {
            # Retrieve file lists with metadata
            $sourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File |
            Select-Object FullName, LastWriteTime, Length

            $destinationFiles = Get-ChildItem -Path $DestinationPath -Recurse -File |
            Select-Object @{Name = 'FullName'; Expression = { $_.FullName -replace [regex]::Escape($DestinationPath), $SourcePath } }, LastWriteTime, Length

            # Compare files
            $differences = Compare-Object -ReferenceObject $sourceFiles -DifferenceObject $destinationFiles -Property FullName, LastWriteTime, Length -PassThru

            # Copy updated and new files
            $differences | ForEach-Object -Parallel {
                $file = $_
                $destinationFile = $file.FullName -replace [regex]::Escape($using:SourcePath), $using:DestinationPath
                $destinationDir = Split-Path -Path $destinationFile

                if (-not (Test-Path -Path $destinationDir)) {
                    New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
                }

                try {
                    Copy-Item -Path $file.FullName -Destination $destinationFile -Force -ErrorAction Stop
                    "Copied: $($file.FullName) -> $destinationFile" | Out-File -Append -FilePath $using:logPath
                }
                catch {
                    "Error copying $($file.FullName): $_" | Out-File -Append -FilePath $using:logPath
                }
            } -ThrottleLimit 5 # Adjust based on your hardware

        }
        catch {
            Write-Error "An error occurred: $_"
        }
    }

    End {
        $elapsedTime = (Get-Date) - $startTime
        Write-Host "Sync completed in $elapsedTime. Log file: $logPath"
    }
}

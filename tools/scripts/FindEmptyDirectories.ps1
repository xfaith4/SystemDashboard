    $path = "G:\Storage\Pictures"
    $empty = "G:\Storage\Empty"
    $stopWatch = [system.diagnostics.stopwatch]::startNew()

	$path = Resolve-Path "$path"
	Write-Progress "Scanning $path for empty folders..."
	[int]$count = 0
	Get-ChildItem "$path" -attributes Directory -recurse -force | Where-Object { @(Get-ChildItem $_.FullName -force).Count -eq 0 } | ForEach-Object {
		"📂$($_.FullName)"
		try {
			Move-Item  -Path $($_.FullName) -Destination $empty
		$count++
			Write-Progress -activity "Moving empty directory $($_.FullName) to $empty" -status "Found $count empty directories" -currentOperation "Moving $($_.FullName) to $empty"
			# Remove-Item $_.FullName -Force -Recurse # Uncomment to delete instead of moving
		}
		catch [System.IO.IOException] {
			Write-Host "❌ Failed to move $($_.FullName): $_"
		}
		catch [System.UnauthorizedAccessException] {
			Write-Host "❌ Unauthorized access to $($_.FullName): $_"
		}
		
        
	}
	Write-Progress -completed " "
	[int]$Elapsed = $stopWatch.Elapsed.TotalSeconds
	"✔️ Found $count empty directories within 📂$path in $elapsed sec" 
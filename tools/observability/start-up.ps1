# Start PromLens in the foreground for initial setup and monitoring (CTRL+C to stop)
$promlensArgs = @(
	"--config.file=`"G:\Storage\BenStuff\Development\Observability\prometheus.yaml`""
	"--storage.tsdb.path=`"G:\Storage\BenStuff\Development\Observability\data`""
)
Start-Process "G:\Storage\BenStuff\Development\Observability\promlens\promlens.exe" -ArgumentList $promlensArgs -WorkingDirectory "G:\Storage\BenStuff\Development\Observability\promlens"

# Wait for PromLens to start and open browser
$attempt = 0
$maxAttempts = 10
while ($attempt -lt $maxAttempts) {
	try {
		$response = Invoke-WebRequest -Uri "http://localhost:9091" -UseBasicParsing -TimeoutSec 2
		if ($response.StatusCode -eq 200) {
			break
		}
	} catch {
		Start-Sleep -Seconds 2
	}
	$attempt++
}
Start-Process http://localhost:9091

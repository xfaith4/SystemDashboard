@echo off
REM System Dashboard Auto-Start Script
REM This script ensures all components are running

echo Starting System Dashboard components...

REM Start scheduled tasks if not running
echo Checking System Dashboard services...
schtasks /query /tn "SystemDashboard-Telemetry" /fo csv | findstr "Running" >nul
if %errorlevel% neq 0 (
    echo Starting Telemetry service...
    schtasks /run /tn "SystemDashboard-Telemetry"
)

schtasks /query /tn "SystemDashboard-LegacyUI" /fo csv | findstr "Running" >nul
if %errorlevel% neq 0 (
    echo Starting Legacy UI service...
    schtasks /run /tn "SystemDashboard-LegacyUI"
)

echo.
echo System Dashboard startup complete!
echo.
echo Web interface should be available at: http://localhost:15000/
echo.
pause

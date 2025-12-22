@echo off
REM System Dashboard Auto-Start Script
REM This script ensures all components are running

echo Starting System Dashboard components...

REM Start PostgreSQL container if not running
echo Checking PostgreSQL container...
docker ps | findstr postgres-container >nul
if %errorlevel% neq 0 (
    echo Starting PostgreSQL container...
    docker start postgres-container
) else (
    echo PostgreSQL container is already running
)

REM Wait for database to be ready
echo Waiting for database to be ready...
timeout /t 5 /nobreak >nul

REM Start scheduled tasks if not running
echo Checking System Dashboard services...
schtasks /query /tn "SystemDashboard-Telemetry" /fo csv | findstr "Running" >nul
if %errorlevel% neq 0 (
    echo Starting Telemetry service...
    schtasks /run /tn "SystemDashboard-Telemetry"
)

schtasks /query /tn "SystemDashboard-WebUI" /fo csv | findstr "Running" >nul
if %errorlevel% neq 0 (
    echo Starting Web UI service...
    schtasks /run /tn "SystemDashboard-WebUI"
)

echo.
set "RepoRoot=%~dp0"
set "Port=5000"
set "PortFile=%RepoRoot%var\webui-port.txt"
if exist "%PortFile%" (
    for /f "usebackq delims=" %%p in ("%PortFile%") do (
        set "Port=%%~p"
        goto :PortReadDone
    )
)
:PortReadDone
echo System Dashboard startup complete!
echo.
echo Web interface should be available at: http://localhost:%Port%
echo Check %PortFile% for the active port if it differs
echo.
pause

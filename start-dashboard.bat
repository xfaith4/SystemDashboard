@echo off
setlocal
REM System Dashboard Auto-Start Script with verbose logging

set "ROOT=%~dp0"
set "LOGDIR=%ROOT%var\log"
set "LOGFILE=%LOGDIR%\start-dashboard.log"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1

call :log "Starting System Dashboard components..."
call :log "User: %USERNAME%"
call :log "Host: %COMPUTERNAME%"

REM Locate docker (works even if PATH is missing it)
set "DOCKER_CMD=docker"
if exist "C:\Program Files\Docker\Docker\resources\bin\docker.exe" (
    set "DOCKER_CMD=C:\Program Files\Docker\Docker\resources\bin\docker.exe"
)

REM Start PostgreSQL container if not running
call :log "Checking PostgreSQL container with %DOCKER_CMD% ..."
"%DOCKER_CMD%" ps --format "{{.Names}}" >>"%LOGFILE%" 2>&1
"%DOCKER_CMD%" ps | findstr postgres-container >nul 2>&1
if %errorlevel% neq 0 (
    call :log "Starting PostgreSQL container..."
    "%DOCKER_CMD%" start postgres-container >>"%LOGFILE%" 2>&1
) else (
    call :log "PostgreSQL container is already running"
)

REM Wait for database to be ready
call :log "Waiting for database to be ready..."
timeout /t 5 /nobreak >nul

REM Start scheduled tasks if not running
call :log "Checking System Dashboard services..."
schtasks /query /tn "SystemDashboard-Telemetry" /fo csv | findstr "Running" >nul 2>&1
if %errorlevel% neq 0 (
    call :log "Starting Telemetry service task..."
    schtasks /run /tn "SystemDashboard-Telemetry" >>"%LOGFILE%" 2>&1
) else (
    call :log "Telemetry service task already running"
)

schtasks /query /tn "SystemDashboard-WebUI" /fo csv | findstr "Running" >nul 2>&1
if %errorlevel% neq 0 (
    call :log "Starting Web UI service task..."
    schtasks /run /tn "SystemDashboard-WebUI" >>"%LOGFILE%" 2>&1
) else (
    call :log "Web UI service task already running"
)

call :log "System Dashboard startup complete! Web interface should be at http://localhost:5000"
echo See log: %LOGFILE%
echo.
pause
goto :eof

:log
setlocal enabledelayedexpansion
for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')"`) do set "ts=%%t"
echo [!ts!] %~1
echo [!ts!] %~1>>"%LOGFILE%"
endlocal
goto :eof

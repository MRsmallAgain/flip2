@echo off
REM TCL Flip2 Manager — launches run-companion.ps1 (dependency check + npm install + Electron).
setlocal
cd /d "%~dp0"
where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-companion.ps1" %*
  exit /b %ERRORLEVEL%
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-companion.ps1" %*
exit /b %ERRORLEVEL%

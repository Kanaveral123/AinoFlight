@echo off
rem Double-click to build; extra arguments go to build.ps1 (for example: build.cmd -Deploy).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
set "code=%errorlevel%"
if "%~1"=="" pause
exit /b %code%

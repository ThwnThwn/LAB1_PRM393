@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0scripts\run.ps1" (
    echo Khong tim thay scripts\run.ps1 trong thu muc project.
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run.ps1"
endlocal

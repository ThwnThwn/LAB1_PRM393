@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0run-public.ps1" (
    echo Khong tim thay run-public.ps1 trong thu muc project.
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-public.ps1"
endlocal

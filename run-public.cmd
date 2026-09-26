@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0scripts\run-public.ps1" (
    echo Khong tim thay scripts\run-public.ps1 trong thu muc project.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run-public.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Script ket thuc voi loi. Ma loi: %ERRORLEVEL%
    pause
)
endlocal

$ErrorActionPreference = 'Stop'

$releaseRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverDirectory = Join-Path $releaseRoot 'server'
$serverExecutable = Join-Path $serverDirectory 'Attendance.Api.exe'
$appDirectory = Join-Path $releaseRoot 'app'
$appExecutable = Join-Path $appDirectory 'fap_attendance_app.exe'
$healthUrl = 'http://127.0.0.1:8080/api/health'
$serverProcess = $null
$logDirectory = Join-Path $env:LOCALAPPDATA 'FAP Attendance\Logs'
$serverOutputLog = Join-Path $logDirectory 'server-output.log'
$serverErrorLog = Join-Path $logDirectory 'server-error.log'

function Test-ServerReady {
    try {
        Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2 | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-RunningDesktopApp {
    @(Get-Process -Name 'fap_attendance_app' -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -eq $appExecutable
            }
            catch {
                $false
            }
        })
}

function Show-StartupError([string] $message) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        $message,
        'FAP Attendance - Loi khoi dong',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
}

try {
    if (-not (Test-Path -LiteralPath $serverExecutable)) {
        throw "Khong tim thay backend: $serverExecutable"
    }

    if (-not (Test-Path -LiteralPath $appExecutable)) {
        throw "Khong tim thay ung dung: $appExecutable"
    }

    if (-not (Test-ServerReady)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        $serverProcess = Start-Process `
            -FilePath $serverExecutable `
            -WorkingDirectory $serverDirectory `
            -WindowStyle Hidden `
            -RedirectStandardOutput $serverOutputLog `
            -RedirectStandardError $serverErrorLog `
            -PassThru

        $serverReady = $false
        for ($attempt = 0; $attempt -lt 120; $attempt++) {
            Start-Sleep -Milliseconds 250
            if (Test-ServerReady) {
                $serverReady = $true
                break
            }

            if ($serverProcess.HasExited) {
                break
            }
        }

        if (-not $serverReady) {
            $details = Get-Content -Raw $serverErrorLog -ErrorAction SilentlyContinue
            throw "Backend khong the khoi dong tai cong 8080.`n$details`n`nLog: $logDirectory"
        }
    }

    $fapDemoUrl = 'http://127.0.0.1:8080/fap-demo/'
    try {
        Start-Process -FilePath $fapDemoUrl | Out-Null
    }
    catch {
        Write-Warning "Khong tu mo duoc cong FAP mo phong: $fapDemoUrl"
    }

    Start-Process `
        -FilePath $appExecutable `
        -WorkingDirectory $appDirectory

    $desktopAppStarted = $false
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        Start-Sleep -Milliseconds 100
        if ((Get-RunningDesktopApp).Count -gt 0) {
            $desktopAppStarted = $true
            break
        }
    }

    if (-not $desktopAppStarted) {
        throw 'Ung dung desktop khong the khoi dong.'
    }

    while ((Get-RunningDesktopApp).Count -gt 0) {
        Start-Sleep -Milliseconds 500
    }
}
catch {
    Show-StartupError $_.Exception.Message
}
finally {
    if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue
    }
}

$ErrorActionPreference = 'Stop'

$releaseRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverDirectory = Join-Path $releaseRoot 'server'
$serverExecutable = Join-Path $serverDirectory 'Attendance.Api.exe'
$appDirectory = Join-Path $releaseRoot 'app'
$appExecutable = Join-Path $appDirectory 'fap_attendance_app.exe'
$healthUrl = 'http://127.0.0.1:8080/api/health'
$logDirectory = Join-Path $env:LOCALAPPDATA 'FAP Attendance\Logs\Public'
$serverOutputLog = Join-Path $logDirectory 'server-output.log'
$serverErrorLog = Join-Path $logDirectory 'server-error.log'
$serverProcess = $null
$tunnel = $null
$appProcess = $null

. (Join-Path $releaseRoot 'public-tunnel-tools.ps1')

function Show-StartupError([string] $message) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        $message,
        'FAP Attendance Public - Loi khoi dong',
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

    try {
        Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2 | Out-Null
        throw 'Cong 8080 dang co backend khac su dung. Hay dong ung dung cu roi chay lai.'
    }
    catch {
        if ($_.Exception.Message -like 'Cong 8080*') { throw }
    }

    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    Remove-Item -LiteralPath $serverOutputLog -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $serverErrorLog -Force -ErrorAction SilentlyContinue

    $teacherToken = New-AttendanceTeacherToken
    $env:ATTENDANCE_PUBLIC_TUNNEL = 'true'
    $env:ATTENDANCE_TEACHER_TOKEN = $teacherToken

    $serverProcess = Start-Process `
        -FilePath $serverExecutable `
        -WorkingDirectory $serverDirectory `
        -WindowStyle Hidden `
        -RedirectStandardOutput $serverOutputLog `
        -RedirectStandardError $serverErrorLog `
        -PassThru

    if (-not (Wait-AttendanceHealth -HealthUrl $healthUrl)) {
        $details = Get-Content -Raw $serverErrorLog -ErrorAction SilentlyContinue
        throw "Backend khong the khoi dong tai cong 8080.`n$details`n`nLog: $logDirectory"
    }

    $tunnel = Start-AttendanceQuickTunnel `
        -OriginUrl 'http://127.0.0.1:8080' `
        -LogDirectory $logDirectory
    if (-not (Wait-AttendanceHealth -HealthUrl "$($tunnel.Url)/api/health" -Attempts 60 -DelayMilliseconds 500)) {
        throw "Tunnel da tao nhung API chua truy cap duoc: $($tunnel.Url)"
    }

    $env:ATTENDANCE_SERVER_URL = $tunnel.Url
    $studentPortalUrl = "$($tunnel.Url)/student/"
    $escapedTeacherToken = [Uri]::EscapeDataString($teacherToken)
    $fapDemoUrl = "$($tunnel.Url)/fap-demo/?teacherToken=$escapedTeacherToken"
    Set-Clipboard -Value $studentPortalUrl -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'PUBLIC DEMO DA SAN SANG' -ForegroundColor Green
    Write-Host "Cong sinh vien: $studentPortalUrl" -ForegroundColor Green
    Write-Host "Cong FAP mo phong (chi giang vien): $fapDemoUrl" -ForegroundColor Green
    Write-Host 'Da sao chep dia chi sinh vien vao clipboard. Dong app de tat tunnel.' -ForegroundColor Yellow
    Write-Host ''

    try {
        Start-Process -FilePath $fapDemoUrl | Out-Null
    }
    catch {
        Write-Warning 'Khong tu mo duoc trinh duyet. Hay mo thu cong duong dan FAP mo phong o tren.'
    }

    $appProcess = Start-Process `
        -FilePath $appExecutable `
        -WorkingDirectory $appDirectory `
        -PassThru
    Wait-Process -Id $appProcess.Id
}
catch {
    Show-StartupError $_.Exception.Message
}
finally {
    if ($null -ne $tunnel -and -not $tunnel.Process.HasExited) {
        Stop-Process -Id $tunnel.Process.Id -ErrorAction SilentlyContinue
    }
    if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue
    }
}

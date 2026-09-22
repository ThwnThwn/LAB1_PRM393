$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$serverProject = Join-Path $projectRoot 'server\Attendance.Api.csproj'
$tunnelTools = Join-Path $projectRoot 'packaging\windows\public-tunnel-tools.ps1'
$healthUrl = 'http://127.0.0.1:8080/api/health'
$logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'fap-attendance-public'
$backendOutputLog = Join-Path $logDirectory 'backend-output.log'
$backendErrorLog = Join-Path $logDirectory 'backend-error.log'
$backendProcess = $null
$tunnel = $null
$previousPublicTunnel = $env:ATTENDANCE_PUBLIC_TUNNEL
$previousTeacherToken = $env:ATTENDANCE_TEACHER_TOKEN
$previousServerUrl = $env:ATTENDANCE_SERVER_URL

. $tunnelTools

try {
    try {
        Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2 | Out-Null
        throw 'Cong 8080 dang co backend khac su dung. Hay dong run.cmd/ung dung cu roi chay lai.'
    }
    catch {
        if ($_.Exception.Message -like 'Cong 8080*') { throw }
    }

    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    Remove-Item -LiteralPath $backendOutputLog -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backendErrorLog -Force -ErrorAction SilentlyContinue

    $teacherToken = New-AttendanceTeacherToken
    $env:ATTENDANCE_PUBLIC_TUNNEL = 'true'
    $env:ATTENDANCE_TEACHER_TOKEN = $teacherToken

    Write-Host 'Dang khoi dong backend o che do public an toan...' -ForegroundColor Cyan
    $dotnetPath = (Get-Command dotnet -ErrorAction Stop).Source
    $backendProcess = Start-Process `
        -FilePath $dotnetPath `
        -ArgumentList @('run', '--project', $serverProject) `
        -WorkingDirectory $projectRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $backendOutputLog `
        -RedirectStandardError $backendErrorLog `
        -PassThru

    if (-not (Wait-AttendanceHealth -HealthUrl $healthUrl)) {
        $details = @(
            Get-Content -Raw $backendOutputLog -ErrorAction SilentlyContinue
            Get-Content -Raw $backendErrorLog -ErrorAction SilentlyContinue
        ) -join "`n"
        throw "Backend khong san sang sau 60 giay.`n$details"
    }

    $tunnel = Start-AttendanceQuickTunnel `
        -OriginUrl 'http://127.0.0.1:8080' `
        -LogDirectory $logDirectory

    $publicHealthUrl = "$($tunnel.Url)/api/health"
    if (-not (Wait-AttendanceHealth -HealthUrl $publicHealthUrl -Attempts 60 -DelayMilliseconds 500)) {
        throw "Tunnel da tao nhung API chua truy cap duoc: $publicHealthUrl"
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
    Write-Host 'Da sao chep dia chi cong sinh vien vao clipboard.' -ForegroundColor DarkGreen
    Write-Host 'Dang mo cong FAP mo phong tren trinh duyet...' -ForegroundColor Cyan
    try {
        Start-Process -FilePath $fapDemoUrl | Out-Null
    }
    catch {
        Write-Warning "Khong tu mo duoc trinh duyet. Hay mo thu cong duong dan FAP mo phong o tren."
    }
    Write-Host 'URL nay chi ton tai trong lan chay hien tai. Nhan Ctrl+C de dung.' -ForegroundColor Yellow
    Write-Host ''

    & flutter run `
        -d windows `
        --dart-define="ATTENDANCE_SERVER_URL=$($tunnel.Url)" `
        --dart-define="ATTENDANCE_TEACHER_TOKEN=$teacherToken"
}
finally {
    if ($null -ne $tunnel -and -not $tunnel.Process.HasExited) {
        Stop-Process -Id $tunnel.Process.Id -ErrorAction SilentlyContinue
    }
    if ($null -ne $backendProcess -and -not $backendProcess.HasExited) {
        Stop-Process -Id $backendProcess.Id -ErrorAction SilentlyContinue
    }

    $env:ATTENDANCE_PUBLIC_TUNNEL = $previousPublicTunnel
    $env:ATTENDANCE_TEACHER_TOKEN = $previousTeacherToken
    $env:ATTENDANCE_SERVER_URL = $previousServerUrl
}

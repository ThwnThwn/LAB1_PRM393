$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverProject = Join-Path $projectRoot 'server\Attendance.Api.csproj'
$healthUrl = 'http://127.0.0.1:8080/api/health'
$backendProcess = $null
$logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'fap-attendance'
$backendOutputLog = Join-Path $logDirectory 'backend-output.log'
$backendErrorLog = Join-Path $logDirectory 'backend-error.log'
$lanAddress = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
    Where-Object { $null -ne $_.IPv4DefaultGateway -and $null -ne $_.IPv4Address } |
    ForEach-Object { $_.IPv4Address.IPAddress } |
    Where-Object { $_ -notlike '127.*' -and $_ -notlike '169.254.*' } |
    Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($lanAddress)) {
    $lanAddress = '127.0.0.1'
    Write-Warning 'Khong tim thay IP LAN. QR chi truy cap duoc tren may tinh nay.'
}

$publicServerUrl = "http://${lanAddress}:8080"
$studentPortalUrl = "$publicServerUrl/student/"
$fapDemoUrl = "$publicServerUrl/fap-demo/"

function Test-BackendReady {
    try {
        Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2 | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

try {
    if (Test-BackendReady) {
        Write-Host 'Backend C# dang chay tai http://localhost:8080' -ForegroundColor Green
    }
    else {
        Write-Host 'Dang khoi dong backend C# tai http://localhost:8080...' -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        $dotnetPath = (Get-Command dotnet -ErrorAction Stop).Source
        $backendProcess = Start-Process `
            -FilePath $dotnetPath `
            -ArgumentList "run --project `"$serverProject`"" `
            -WorkingDirectory $projectRoot `
            -WindowStyle Hidden `
            -RedirectStandardOutput $backendOutputLog `
            -RedirectStandardError $backendErrorLog `
            -PassThru

        $backendReady = $false
        for ($attempt = 0; $attempt -lt 120; $attempt++) {
            Start-Sleep -Milliseconds 500
            if (Test-BackendReady) {
                $backendReady = $true
                break
            }

            if ($backendProcess.HasExited) {
                $backendOutput = Get-Content -Raw $backendOutputLog -ErrorAction SilentlyContinue
                $backendError = Get-Content -Raw $backendErrorLog -ErrorAction SilentlyContinue
                throw "Backend C# khoi dong that bai.`n$backendOutput`n$backendError"
            }

            if (($attempt + 1) % 10 -eq 0) {
                Write-Host "Van dang khoi dong backend... $([math]::Round(($attempt + 1) / 2)) giay" -ForegroundColor DarkGray
            }
        }

        if (-not $backendReady) {
            $backendOutput = Get-Content -Raw $backendOutputLog -ErrorAction SilentlyContinue
            $backendError = Get-Content -Raw $backendErrorLog -ErrorAction SilentlyContinue
            throw "Backend C# khong san sang tai cong 8080 sau 60 giay.`n$backendOutput`n$backendError"
        }

        Write-Host 'Backend C# da san sang tai http://localhost:8080' -ForegroundColor Green
    }

    Write-Host "Cong sinh vien trong QR: $studentPortalUrl" -ForegroundColor Green
    Write-Host "Cong FAP mo phong: $fapDemoUrl" -ForegroundColor Green
    Write-Host 'Dang mo cong FAP mo phong tren trinh duyet...' -ForegroundColor Cyan
    try {
        Start-Process -FilePath $fapDemoUrl | Out-Null
    }
    catch {
        Write-Warning "Khong tu mo duoc trinh duyet. Hay mo thu cong: $fapDemoUrl"
    }
    Write-Host 'Dang mo ung dung Flutter Windows cho giang vien...' -ForegroundColor Cyan
    & flutter run `
        -d windows `
        --dart-define="ATTENDANCE_SERVER_URL=$publicServerUrl"
}
finally {
    if ($null -ne $backendProcess -and -not $backendProcess.HasExited) {
        Stop-Process -Id $backendProcess.Id
    }
}

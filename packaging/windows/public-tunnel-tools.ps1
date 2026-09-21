function Resolve-CloudflaredPath {
    $command = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $candidatePaths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\cloudflared.exe'),
        (Join-Path $env:ProgramFiles 'cloudflared\cloudflared.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'cloudflared\cloudflared.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidatePaths) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw @'
Chua cai cloudflared va khong tim thay winget.
Tai ban Windows 64-bit tai:
https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/
'@
    }

    Write-Host 'Chua co cloudflared. Dang cai mien phi bang winget...' -ForegroundColor Cyan
    & $winget.Source install `
        --id Cloudflare.cloudflared `
        --exact `
        --silent `
        --accept-source-agreements `
        --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Khong the cai cloudflared (winget exit code $LASTEXITCODE)."
    }

    $command = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    foreach ($candidate in $candidatePaths) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw 'Da cai cloudflared nhung chua tim thay file thuc thi. Hay mo lai terminal va thu lai.'
}

function New-AttendanceTeacherToken {
    $bytes = New-Object byte[] 32
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }

    return -join ($bytes | ForEach-Object { $_.ToString('X2') })
}

function Start-AttendanceQuickTunnel {
    param(
        [Parameter(Mandatory = $true)]
        [string] $OriginUrl,

        [Parameter(Mandatory = $true)]
        [string] $LogDirectory
    )

    $cloudflaredPath = Resolve-CloudflaredPath
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    $outputLog = Join-Path $LogDirectory 'cloudflared-output.log'
    $errorLog = Join-Path $LogDirectory 'cloudflared-error.log'
    Remove-Item -LiteralPath $outputLog -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $errorLog -Force -ErrorAction SilentlyContinue

    Write-Host 'Dang tao duong dan HTTPS cong khai mien phi...' -ForegroundColor Cyan
    $process = Start-Process `
        -FilePath $cloudflaredPath `
        -ArgumentList @('tunnel', '--no-autoupdate', '--url', $OriginUrl) `
        -WindowStyle Hidden `
        -RedirectStandardOutput $outputLog `
        -RedirectStandardError $errorLog `
        -PassThru

    $publicUrl = $null
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        Start-Sleep -Milliseconds 250

        $logText = @(
            Get-Content -Raw $outputLog -ErrorAction SilentlyContinue
            Get-Content -Raw $errorLog -ErrorAction SilentlyContinue
        ) -join "`n"
        $match = [regex]::Match(
            $logText,
            'https://[a-z0-9-]+\.trycloudflare\.com',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($match.Success) {
            $publicUrl = $match.Value.TrimEnd('/')
            break
        }

        if ($process.HasExited) {
            throw "Cloudflare Tunnel dung dot ngot.`n$logText"
        }
    }

    if ([string]::IsNullOrWhiteSpace($publicUrl)) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        }
        throw "Khong lay duoc URL Cloudflare sau 30 giay. Xem log: $errorLog"
    }

    [PSCustomObject]@{
        Process = $process
        Url = $publicUrl
        OutputLog = $outputLog
        ErrorLog = $errorLog
    }
}

function Wait-AttendanceHealth {
    param(
        [Parameter(Mandatory = $true)]
        [string] $HealthUrl,

        [int] $Attempts = 120,

        [int] $DelayMilliseconds = 500
    )

    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        try {
            Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 3 | Out-Null
            return $true
        }
        catch {
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }

    return $false
}

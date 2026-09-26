# Kiem tra port 8080
try {
    Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/health' -TimeoutSec 2 | Out-Null
    Write-Host 'PORT 8080: DANG CO BACKEND CHAY - day la nguyen nhan loi! Hay dong run.cmd truoc.'
} catch {
    $msg = $_.Exception.Message
    if ($msg -match 'refused|connect|Unable') {
        Write-Host 'PORT 8080: Trong (OK)'
    } else {
        Write-Host "PORT 8080 check error: $msg"
    }
}

# Kiem tra dotnet
$d = Get-Command dotnet -ErrorAction SilentlyContinue
if ($null -ne $d) {
    $ver = dotnet --version 2>&1
    Write-Host "DOTNET: $ver (OK)"
} else {
    Write-Host 'DOTNET: KHONG TIM THAY - can cai .NET SDK'
}

# Kiem tra flutter
$fl = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -ne $fl) {
    Write-Host 'FLUTTER: Co (OK)'
} else {
    Write-Host 'FLUTTER: KHONG TIM THAY'
}

# Kiem tra server csproj
if (Test-Path 'server\Attendance.Api.csproj') {
    Write-Host 'SERVER PROJECT: Co (OK)'
} else {
    Write-Host 'SERVER PROJECT: KHONG CO - thu muc server thieu file csproj'
}

# Kiem tra tunnel tools
if (Test-Path 'packaging\windows\public-tunnel-tools.ps1') {
    Write-Host 'TUNNEL TOOLS: Co (OK)'
} else {
    Write-Host 'TUNNEL TOOLS: KHONG CO'
}

# Kiem tra cloudflared
$cf = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($null -ne $cf) {
    $cv = cloudflared --version 2>&1 | Select-Object -First 1
    Write-Host "CLOUDFLARED: $cv (OK)"
} else {
    Write-Host 'CLOUDFLARED: Chua cai (script se tu tai ve)'
}

Write-Host ''
Write-Host 'Kiem tra xong. Nhan Enter de dong...'
Read-Host

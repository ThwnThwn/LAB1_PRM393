param(
    [string] $OutputDirectory = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$packageName = 'FAP-Attendance-Windows-x64'
$packageDirectory = Join-Path $outputRoot $packageName
$zipPath = Join-Path $outputRoot "$packageName.zip"
$flutterRelease = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$serverProject = Join-Path $projectRoot 'server\Attendance.Api.csproj'
$launcherDirectory = Join-Path $projectRoot 'packaging\windows'
$existingDataDirectory = Join-Path $packageDirectory 'server\App_Data'
$preservedDataDirectory = $null

if ($outputRoot -eq $projectRoot -or $packageDirectory -eq $projectRoot) {
    throw 'OutputDirectory phai la thu muc con rieng, khong duoc la thu muc goc project.'
}

foreach ($commandName in @('flutter', 'dotnet')) {
    if ($null -eq (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Khong tim thay lenh $commandName trong PATH."
    }
}

Write-Host '1/5 - Lay Flutter packages...' -ForegroundColor Cyan
& flutter pub get --offline
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get that bai.' }

Write-Host '2/5 - Build Flutter Windows release...' -ForegroundColor Cyan
& flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows build that bai.' }

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
if (Test-Path -LiteralPath $existingDataDirectory) {
    $preservedDataDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("fap-attendance-data-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $preservedDataDirectory -Force | Out-Null
    Get-ChildItem -LiteralPath $existingDataDirectory -Force | Copy-Item -Destination $preservedDataDirectory -Recurse -Force
    Write-Host 'Da tam giu cau hinh Google Sheets va cache cua ban dang chay.' -ForegroundColor DarkCyan
}
if (Test-Path -LiteralPath $packageDirectory) {
    Remove-Item -LiteralPath $packageDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null

Write-Host '3/5 - Publish backend .NET tu chua runtime...' -ForegroundColor Cyan
$serverOutput = Join-Path $packageDirectory 'server'
& dotnet publish $serverProject `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None `
    -o $serverOutput
if ($LASTEXITCODE -ne 0) { throw 'Backend publish that bai.' }

$publishedData = Join-Path $serverOutput 'App_Data'
if (Test-Path -LiteralPath $publishedData) {
    Remove-Item -LiteralPath $publishedData -Recurse -Force
}

Write-Host '4/5 - Dong goi desktop, cong sinh vien va cong FAP mo phong...' -ForegroundColor Cyan
Copy-Item -LiteralPath $flutterRelease -Destination (Join-Path $packageDirectory 'app') -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs') -Destination (Join-Path $packageDirectory 'docs') -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot 'fap-demo') -Destination (Join-Path $packageDirectory 'fap-demo') -Recurse
Copy-Item -Path (Join-Path $launcherDirectory '*') -Destination $packageDirectory -Recurse

Write-Host '5/5 - Tao file ZIP...' -ForegroundColor Cyan
Compress-Archive -LiteralPath $packageDirectory -DestinationPath $zipPath -CompressionLevel Optimal

if ($null -ne $preservedDataDirectory -and (Test-Path -LiteralPath $preservedDataDirectory)) {
    $restoredDataDirectory = Join-Path $serverOutput 'App_Data'
    New-Item -ItemType Directory -Path $restoredDataDirectory -Force | Out-Null
    Get-ChildItem -LiteralPath $preservedDataDirectory -Force | Copy-Item -Destination $restoredDataDirectory -Recurse -Force
    Remove-Item -LiteralPath $preservedDataDirectory -Recurse -Force
    Write-Host 'Da khoi phuc cau hinh Google Sheets cho ban dang chay (file ZIP van sach).' -ForegroundColor DarkCyan
}

Write-Host ''
Write-Host 'Da tao ban Windows portable:' -ForegroundColor Green
Write-Host $zipPath -ForegroundColor Green

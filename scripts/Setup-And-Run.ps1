#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
$localDotnet = Join-Path $root '.tools\dotnet\dotnet.exe'
$dotnet = $null

Write-Host ''
Write-Host '  ArchMCP Hub - Build and Launch (v1.0.0)' -ForegroundColor Cyan
Write-Host '  ---------------------------------------' -ForegroundColor DarkGray
Write-Host '  This script builds and launches the ArchMCP Hub desktop app locally.' -ForegroundColor Gray
Write-Host ''

$globalDotnet = Get-Command dotnet -ErrorAction SilentlyContinue | Select-Object -First 1
if ($globalDotnet -and (Test-Path -LiteralPath $globalDotnet.Source)) {
    $sdkList = & $globalDotnet.Source --list-sdks 2>$null
    if ($sdkList | Where-Object { $_ -match '^(8|9|10)\.' }) { $dotnet = $globalDotnet.Source }
}

if (-not $dotnet -and (Test-Path -LiteralPath $localDotnet)) {
    $sdkList = & $localDotnet --list-sdks 2>$null
    if ($sdkList | Where-Object { $_ -match '^(8|9|10)\.' }) { $dotnet = $localDotnet }
}

if (-not $dotnet) {
    Write-Host '.NET SDK (8.0/9.0/10.0) was not found. Installing a local copy in .tools\dotnet...' -ForegroundColor Yellow
    $toolsDir = Join-Path $root '.tools'
    $dotnetDir = Join-Path $toolsDir 'dotnet'
    New-Item -ItemType Directory -Force -Path $toolsDir, $dotnetDir | Out-Null
    $installer = Join-Path $toolsDir 'dotnet-install.ps1'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer -UseBasicParsing
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Channel 10.0 -Quality GA -InstallDir $dotnetDir
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $localDotnet)) {
        Write-Host 'Channel 10.0 not available on this endpoint; falling back to LTS channel 8.0...' -ForegroundColor Yellow
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Channel LTS -Quality GA -InstallDir $dotnetDir
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $localDotnet)) {
        throw 'The .NET SDK installation failed. Check your internet connection and try again.'
    }
    $dotnet = $localDotnet
}

Write-Host 'Using SDK:' -ForegroundColor Gray
& $dotnet --version
if ($LASTEXITCODE -ne 0) { throw '.NET SDK is not working.' }

Push-Location $root
try {
    Write-Host "`n[1/4] Restoring packages..." -ForegroundColor Cyan
    & $dotnet restore '.\ArchMCP.Hub.sln'
    if ($LASTEXITCODE -ne 0) { throw 'Package restore failed.' }

    Write-Host "`n[2/4] Building solution..." -ForegroundColor Cyan
    & $dotnet build '.\ArchMCP.Hub.sln' -c Release --no-restore
    if ($LASTEXITCODE -ne 0) { throw 'Build failed. See compiler errors above.' }

    Write-Host "`n[3/4] Running automated tests..." -ForegroundColor Cyan
    & $dotnet test '.\ArchMCP.Hub.sln' -c Release --no-build
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed. The app will not be launched until this is resolved.' }

    Write-Host "`n[4/4] Publishing self-contained portable app..." -ForegroundColor Cyan
    $publishDir = Join-Path $root 'dist\win-x64'
    & $dotnet publish '.\src\ArchMCP.Hub.App\ArchMCP.Hub.App.csproj' -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $publishDir
    if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }

    $exe = Join-Path $publishDir 'ArchMCP.Hub.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw "Published executable was not found at $exe" }
    Write-Host "`nBuild and tests succeeded. Launching ArchMCP Hub..." -ForegroundColor Green
    $process = Start-Process -FilePath $exe -WorkingDirectory $publishDir -PassThru
    Start-Sleep -Seconds 3
    $process.Refresh()
    if ($process.HasExited) {
        Write-Host "The app exited during startup (exit code: $($process.ExitCode))." -ForegroundColor Red
        Write-Host 'If a startup dialog did not appear, check %LOCALAPPDATA%\ArchMCP Hub\Logs\startup.log' -ForegroundColor Yellow
        throw 'ArchMCP Hub built successfully but did not remain running.'
    }
    Write-Host "Application process started: PID $($process.Id)" -ForegroundColor Green
    Write-Host "Executable: $exe" -ForegroundColor Green
}
finally {
    Pop-Location
}

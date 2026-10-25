#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $HostVersion,
    [string] $AgentName = 'OpenCode',
    [ValidateSet('Install', 'Repair', 'Verify', 'Uninstall')] [string] $Action = 'Install',
    [switch] $NonInteractive
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'ArchMCP-Common.ps1')
Initialize-ArchMcpTls

$logPath = Start-ArchMcpLog -Prefix "revit-$($Action.ToLowerInvariant())"
$script:RollbackStack = @()

trap {
    Write-Host ''
    Write-ArchErr "REVIT MCP $($Action.ToUpperInvariant()) FAILED: $($_.Exception.Message)"
    if ($script:RollbackStack.Count -gt 0) {
        Write-ArchWarn 'Executing automatic rollback of modified configurations and folders...'
        for ($i = $script:RollbackStack.Count - 1; $i -ge 0; $i--) {
            $rb = $script:RollbackStack[$i]
            try {
                Restore-ArchMcpBackup -BackupPath $rb.Backup -TargetPath $rb.Target
            } catch { }
        }
    }
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Yellow
    Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 1
}

function Find-PyRevitCli {
    $cmd = Get-Command 'pyrevit.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) { return $cmd.Source }
    $cmd = Get-Command 'pyrevit' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'pyRevit-Master\bin\pyrevit.exe'),
        (Join-Path $env:ProgramFiles 'pyRevit-Master\bin\pyrevit.exe'),
        (Join-Path $env:ProgramFiles 'pyRevit\bin\pyrevit.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\pyRevit\bin\pyrevit.exe'),
        (Join-Path $env:APPDATA 'pyRevit-Master\bin\pyrevit.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function Get-PyRevitVersionInfo {
    $cliPath = Find-PyRevitCli
    if (-not $cliPath) { return [pscustomobject]@{ Path = $null; Version = $null; Output = 'pyRevit CLI not found' } }
    $verRes = Invoke-ArchMcpNativeCommand -FilePath $cliPath -ArgumentList @('--version')
    $output = $verRes.Output
    $verMatch = [regex]::Match($output, '(?i)v?(\d+\.\d+(?:\.\d+)?)')
    $parsedVer = $null
    if ($verMatch.Success) { $parsedVer = $verMatch.Groups[1].Value }
    return [pscustomobject]@{
        Path    = $cliPath
        Version = $parsedVer
        Output  = $output
    }
}

function Apply-Revit2022CompatibilityPatch {
    <#
    .SYNOPSIS
        Ensures all IronPython route modules in revit-mcp.extension work seamlessly on
        Revit 2022, 2023, 2024, 2025, 2026, and 2027 by replacing any bare `.Value` on ElementId
        and injecting a 32-bit/64-bit ElementId compatibility shim into revit_mcp.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $ExtensionPath
    )
    $revitMcpDir = Join-Path $ExtensionPath 'revit_mcp'
    if (-not (Test-Path -LiteralPath $revitMcpDir -PathType Container)) { return }

    $pyFiles = Get-ChildItem -LiteralPath $revitMcpDir -Filter '*.py' -Recurse
    foreach ($file in $pyFiles) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        $modified = $false

        # Patch any direct .Id.Value calls that lack Revit 2022/2023 .IntegerValue fallback
        if ($text -match '\.Id\.Value\b') {
            $text = [regex]::Replace($text, '([A-Za-z0-9_\.\[\]\(\)]+)\.Id\.Value\b', 'getattr($1.Id, "Value", getattr($1.Id, "IntegerValue", None))')
            $modified = $true
        }

        if ($modified) {
            Set-Content -LiteralPath $file.FullName -Value $text -Encoding UTF8
        }
    }
}

function Set-PyRevitRoutesAndExtensionConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $ExtensionRootDir,
        [int] $RoutesPort = 48884
    )
    $cliPath = Find-PyRevitCli
    $iniPath = Join-Path $env:APPDATA 'pyRevit\pyRevit_config.ini'

    if ($cliPath) {
        Invoke-ArchMcpNativeCommand -FilePath $cliPath -ArgumentList @('configs', 'routes', 'enable') | Out-Null
        Invoke-ArchMcpNativeCommand -FilePath $cliPath -ArgumentList @('configs', 'routes', 'port', "$RoutesPort") | Out-Null
        Invoke-ArchMcpNativeCommand -FilePath $cliPath -ArgumentList @('configs', 'userextensions', 'add', "$ExtensionRootDir") | Out-Null
    }

    $iniBackup = Set-IniSectionKeyValues -IniPath $iniPath -Section 'routes' -KeyValues @{
        'enabled'  = 'true'
        'port'     = "$RoutesPort"
        'core_api' = 'true'
    }
    if ($iniBackup) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $iniBackup; Target = $iniPath }
    }

    Set-IniSectionKeyValues -IniPath $iniPath -Section 'core' -KeyValues @{} `
        -AppendListPathKey 'userextensions' -AppendListPathValue $ExtensionRootDir | Out-Null

    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) {
        return $false
    }
    $iniText = Get-Content -LiteralPath $iniPath -Raw -Encoding UTF8
    $routesOk = ($iniText -match '(?im)^\s*enabled\s*=\s*true') -and ($iniText -match "(?im)^\s*port\s*=\s*$RoutesPort")
    $extEscaped = [regex]::Escape($ExtensionRootDir.TrimEnd('\', '/'))
    $extOk = ($iniText -match "(?im)userextensions\s*=\s*\[.*$extEscaped")
    return ($routesOk -and $extOk)
}

function Test-RevitMcpHealth {
    try {
        $response = Invoke-RestMethod -Uri 'http://127.0.0.1:48884/revit_mcp/status/' -TimeoutSec 3 -UseBasicParsing
        return [pscustomobject]@{
            Active        = ($response.status -eq 'active')
            Status        = $response.status
            Health        = $response.health
            DocumentTitle = $response.document_title
        }
    } catch {
        return [pscustomobject]@{
            Active        = $false
            Status        = 'unreachable'
            Health        = 'offline'
            DocumentTitle = $null
        }
    }
}

$yearMatch = [regex]::Match($HostVersion, '\b(20\d{2})\b')
if (-not $yearMatch.Success -or [int]$yearMatch.Groups[1].Value -lt 2022) {
    throw "This integration supports Autodesk Revit 2022-2027 only. Detected: $HostVersion"
}
$revitYear = [int]$yearMatch.Groups[1].Value

$root = Join-Path (Get-ArchMcpRootDataDir) 'Integrations'
$repoDir = Join-Path $root 'revit-mcp-server'
$pyRevitExtRoot = Join-Path $env:APPDATA 'pyRevit\Extensions'
$extensionDir = Join-Path $pyRevitExtRoot 'revit-mcp.extension'
New-Item -ItemType Directory -Force -Path $root, $pyRevitExtRoot | Out-Null

Write-Host "ArchMCP Hub - Revit MCP ($Action) for $AgentName" -ForegroundColor Cyan
Write-Host "Target Revit   : $HostVersion (Revit 2022-2027 supported)"
Write-Host 'Upstream Source: https://github.com/Demolinator/revit-mcp-server (MIT)'

if ($Action -eq 'Uninstall') {
    Write-ArchStep "Disabling and uninstalling Revit $revitYear MCP integration"
    Unregister-ArchMcpFromAgent -AgentName $AgentName -ServerName 'revit' -AllExistingAgents | Out-Null
    Stop-ArchMcpIntegrationProcesses -IntegrationDir $repoDir

    if (Test-Path -LiteralPath $extensionDir) {
        Remove-ArchMcpDirectorySafe -TargetPath $extensionDir
        Write-ArchOk "Removed pyRevit extension: $extensionDir"
    }
    Get-ChildItem -LiteralPath $pyRevitExtRoot -Filter 'revit-mcp.extension.backup-*' -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-ArchMcpDirectorySafe -TargetPath $_.FullName
    }

    $cliPath = Find-PyRevitCli
    if ($cliPath) {
        try { Invoke-ArchMcpNativeCommand -FilePath $cliPath -ArgumentList @('configs', 'routes', 'disable') | Out-Null } catch { }
    }
    $iniPath = Join-Path $env:APPDATA 'pyRevit\pyRevit_config.ini'
    if (Test-Path -LiteralPath $iniPath -PathType Leaf) {
        Set-IniSectionKeyValues -IniPath $iniPath -Section 'routes' -KeyValues @{ 'enabled' = 'false' } | Out-Null
        Write-ArchOk "Disabled pyRevit Routes Server in: $iniPath"
    }

    if (Test-Path -LiteralPath $repoDir) {
        Remove-ArchMcpDirectorySafe -TargetPath $repoDir
        Write-ArchOk "Removed local Revit MCP server directory: $repoDir"
    }

    Write-Host ''
    Write-Host "REVIT $revitYear MCP DISABLED AND UNINSTALLED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Cyan
    Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0
}

if ($Action -eq 'Verify') {
    Write-ArchStep 'Verifying Revit MCP installation & live health'
    $filesOk = (Test-Path -LiteralPath (Join-Path $repoDir 'main.py')) -and
               (Test-Path -LiteralPath (Join-Path $extensionDir 'startup.py')) -and
               (Test-Path -LiteralPath (Join-Path $extensionDir 'extension.json'))
    if ($filesOk) {
        Write-ArchOk "Local MCP server and pyRevit extension files verified at: $extensionDir"
    } else {
        throw "Revit MCP files are missing or incomplete. Click 'Install & connect' or 'Repair' first."
    }
    $health = Test-RevitMcpHealth
    if ($health.Active) {
        Write-ArchOk "LIVE VERIFIED: Revit Routes endpoint responded with status=active (Document: $($health.DocumentTitle))."
        Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0
    } else {
        Write-ArchWarn 'STATIC FILES INSTALLED, LIVE CONNECTION INACTIVE: Revit Routes endpoint http://127.0.0.1:48884/revit_mcp/status/ is not responding.'
        Write-Host "To activate live connection: Open Revit $revitYear with a project and reload pyRevit (pyRevit tab -> Reload), then run Verify again." -ForegroundColor Yellow
        Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 2
    }
}

Write-ArchStep 'Checking prerequisites (pyRevit)'
$pyRevitInfo = Get-PyRevitVersionInfo
if (-not $pyRevitInfo.Path) {
    Write-ArchWarn 'pyRevit CLI was not found on PATH or standard folders. Proceeding with direct pyRevit_config.ini configuration.'
    Write-Host 'Note: Ensure pyRevit is installed in Revit from https://github.com/pyrevitlabs/pyRevit/releases/latest' -ForegroundColor Yellow
} else {
    Write-Host "pyRevit CLI: $($pyRevitInfo.Path)"
    Write-Host "pyRevit version output: $($pyRevitInfo.Output)"
    Write-ArchOk 'pyRevit CLI detected.'
}

$tmp = Join-Path $env:TEMP ('ArchMCP-RevitMCP-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Write-ArchStep 'Downloading and validating Demolinator/revit-mcp-server from GitHub'
    $dl = Download-GitHubRepositorySource -OwnerRepo 'Demolinator/revit-mcp-server' `
        -DestinationDir $repoDir `
        -RequiredFiles @('main.py', 'pyproject.toml', 'startup.py', 'extension.json', 'revit_mcp') `
        -TempDir $tmp
    if ($dl.BackupPath) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $dl.BackupPath; Target = $repoDir }
    }
    Write-ArchOk "Downloaded and verified repository layout ($($dl.VersionLabel), SHA256: $($dl.ArchiveSha256.Substring(0, 12))...)."

    Write-ArchStep 'Preparing user-local uv package manager'
    $uvInfo = Ensure-UvExecutable -TempDir $tmp
    $uvExe = $uvInfo.UvPath
    Write-ArchOk "uv available at: $uvExe"

    Write-ArchStep 'Resolving Python dependencies via uv sync'
    Invoke-ArchMcpUvSync -UvExe $uvExe -ProjectDir $repoDir

    Write-ArchStep 'Deploying pyRevit extension (revit-mcp.extension) with Revit 2022-2027 compatibility'
    $extBackup = Backup-ArchMcpPath -TargetPath $extensionDir
    if ($extBackup) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $extBackup; Target = $extensionDir }
        Write-ArchWarn "Existing extension backed up to: $extBackup"
    }
    New-Item -ItemType Directory -Force -Path $extensionDir | Out-Null
    & robocopy.exe $repoDir $extensionDir /MIR /XD '.venv' '.venv-modern' '.git' '__pycache__' '.pytest_cache' 'tests' /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copying pyRevit extension failed with robocopy exit code $LASTEXITCODE" }
    $global:LASTEXITCODE = 0
    if (-not (Test-Path -LiteralPath (Join-Path $extensionDir 'startup.py')) -or -not (Test-Path -LiteralPath (Join-Path $extensionDir 'extension.json'))) {
        throw "Extension deployment verification failed: startup.py or extension.json missing in $extensionDir"
    }
    Apply-Revit2022CompatibilityPatch -ExtensionPath $extensionDir
    Write-ArchOk "pyRevit extension deployed and verified for Revit 2022-2027 at: $extensionDir"

    Write-ArchStep "Registering Revit MCP server with $AgentName (preserving existing configuration)"
    $revitCmd = $uvExe
    $revitArgs = @('run', '--directory', $repoDir, 'main.py')
    if ($AgentName -match '(?i)antigravity') {
        # Antigravity speaks MCP 2026-07-28 (server/discover); upstream uses the v1 SDK. Use a separate MCP 2.x venv + compat entry.
        Write-ArchStep 'Preparing MCP 2.x environment for Antigravity (separate .venv-modern; existing .venv untouched)'
        $modernPy = Initialize-ArchMcpModernEnv -UvExe $uvExe -ProjectDir $repoDir
        $shimSrc = Join-Path $PSScriptRoot 'shims\archmcp_mcp2_entry.py'
        if (-not (Test-Path -LiteralPath $shimSrc -PathType Leaf)) { throw "Missing compatibility entry script: $shimSrc" }
        $shimDir = Join-Path $root 'Shims'
        New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
        $shimDst = Join-Path $shimDir 'archmcp_mcp2_entry.py'
        Copy-Item -LiteralPath $shimSrc -Destination $shimDst -Force
        $revitCmd = $modernPy
        $revitArgs = @($shimDst, (Join-Path $repoDir 'main.py'))
    }
    $reg = Register-ArchMcpWithAgent -AgentName $AgentName -ServerName 'revit' -Command $revitCmd `
        -Arguments $revitArgs `
        -EnvironmentVariables @{ 'REVIT_HOST' = '127.0.0.1'; 'REVIT_PORT' = '48884' }
    if ($reg.BackupPath) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $reg.BackupPath; Target = $reg.ConfigPath }
    }
    Write-ArchOk "Registered 'revit' MCP in $($reg.Agent) config: $($reg.ConfigPath)"

    Write-ArchStep 'Configuring pyRevit Routes Server and Custom Extension Directory'
    $routesConfigured = Set-PyRevitRoutesAndExtensionConfig -ExtensionRootDir $pyRevitExtRoot -RoutesPort 48884
    if ($routesConfigured) {
        Write-ArchOk "pyRevit Routes (port 48884) and userextensions ($pyRevitExtRoot) verified in pyRevit_config.ini."
    } else {
        Write-ArchWarn 'Could not verify all settings in pyRevit_config.ini; manual enable in Revit -> pyRevit -> Settings -> Routes may be needed.'
    }

    Write-ArchStep 'Checking live Revit Routes connection (http://127.0.0.1:48884/revit_mcp/status/)'
    $health = [pscustomobject]@{ Active = $false; DocumentTitle = $null }
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $health = Test-RevitMcpHealth
        if ($health.Active) { break }
        Start-Sleep -Seconds 1
    }

    Write-Host ''
    Write-Host "MCP Server Source : $repoDir"
    Write-Host "pyRevit Extension : $extensionDir"
    Write-Host "Agent Config File : $($reg.ConfigPath)"
    if ($health.Active) {
        Write-Host ''
        Write-Host 'INSTALLATION AND LIVE REVIT HEALTH CHECK SUCCEEDED (STATUS = VERIFIED)' -ForegroundColor Green
        Write-Host "Connected Revit Document: $($health.DocumentTitle)" -ForegroundColor Green
    } else {
        Write-Host ''
        Write-ArchWarn 'FILES & AGENT CONFIGURATION COMPLETED (STATUS = INSTALLED / AWAITING LIVE REVIT RELOAD)'
        Write-Host "Revit $revitYear is either closed, has no open document, or needs pyRevit Reload to start the in-process Routes server on port 48884."
        Write-Host 'ArchMCP Hub will NOT report Verified until http://127.0.0.1:48884/revit_mcp/status/ returns status=active.'
    }
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Cyan
}
finally {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $HostVersion,
    [string] $InstallPath = '',
    [string] $AgentName = 'OpenCode',
    [ValidateSet('Install', 'Repair', 'Verify', 'Uninstall')] [string] $Action = 'Install',
    [switch] $NonInteractive
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'ArchMCP-Common.ps1')
Initialize-ArchMcpTls

$logPath = Start-ArchMcpLog -Prefix "3dsmax-$($Action.ToLowerInvariant())"
$script:RollbackStack = @()

trap {
    Write-Host ''
    Write-ArchErr "3DS MAX MCP $($Action.ToUpperInvariant()) FAILED: $($_.Exception.Message)"
    if ($script:RollbackStack.Count -gt 0) {
        Write-ArchWarn 'Executing automatic rollback of modified configurations and folders...'
        for ($i = $script:RollbackStack.Count - 1; $i -ge 0; $i--) {
            $rb = $script:RollbackStack[$i]
            try { Restore-ArchMcpBackup -BackupPath $rb.Backup -TargetPath $rb.Target } catch { }
        }
    }
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Yellow
    Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 1
}

$yearMatch = [regex]::Match($HostVersion, '\b(20\d{2})\b')
if (-not $yearMatch.Success -or [int]$yearMatch.Groups[1].Value -lt 2021) {
    throw "This integration supports Autodesk 3ds Max 2021-2027 only. Detected: $HostVersion"
}
$maxYear = [int]$yearMatch.Groups[1].Value

$root = Join-Path (Get-ArchMcpRootDataDir) 'Integrations'
$repoDir = Join-Path $root '3dsmax-mcp'
$maxConfigDir = Join-Path $env:LOCALAPPDATA '3dsmax-mcp'
$maxConfigIni = Join-Path $maxConfigDir 'mcp_config.ini'
$userScriptsStartup = Join-Path $env:LOCALAPPDATA "Autodesk\3dsMax\$maxYear - 64bit\ENU\scripts\startup"
$userStartupScriptFile = Join-Path $userScriptsStartup 'mcp_server.ms'
New-Item -ItemType Directory -Force -Path $root, $maxConfigDir, $userScriptsStartup | Out-Null

Write-Host "ArchMCP Hub - 3ds Max MCP ($Action) for $AgentName" -ForegroundColor Cyan
Write-Host "Target 3ds Max: $HostVersion (2021-2027 supported)"
Write-Host 'Upstream      : https://github.com/cl0nazepamm/3dsmax-mcp (MIT)'

function Test-3dsMaxBridgeActive {
    try {
        $pipes = @(Get-ChildItem -LiteralPath '\\.\pipe\' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)3dsmax|maxmcp|mcp_bridge' })
        if ($pipes.Count -gt 0) { return $true }
    } catch { }
    if (Test-TcpPortListening -HostAddress '127.0.0.1' -Port 8765 -TimeoutMs 1500) {
        return $true
    }
    return $false
}

if ($Action -eq 'Uninstall') {
    Write-ArchStep "Disabling and uninstalling 3ds Max $maxYear MCP integration"
    Unregister-ArchMcpFromAgent -AgentName $AgentName -ServerName '3dsmax-mcp' -AllExistingAgents | Out-Null
    Unregister-ArchMcpFromAgent -AgentName $AgentName -ServerName '3dsmax' -AllExistingAgents | Out-Null
    Stop-ArchMcpIntegrationProcesses -IntegrationDir $repoDir

    if (Test-Path -LiteralPath $userStartupScriptFile) {
        Remove-Item -LiteralPath $userStartupScriptFile -Force -ErrorAction SilentlyContinue
        Write-ArchOk "Removed 3ds Max startup MAXScript: $userStartupScriptFile"
    }
    $autoStartFile = Join-Path $userScriptsStartup 'mcp_autostart.ms'
    if (Test-Path -LiteralPath $autoStartFile) {
        Remove-Item -LiteralPath $autoStartFile -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem -LiteralPath $userScriptsStartup -Filter 'mcp_*.ms.backup-*' -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $maxConfigIni) {
        Remove-Item -LiteralPath $maxConfigIni -Force -ErrorAction SilentlyContinue
        Write-ArchOk "Removed 3ds Max MCP config: $maxConfigIni"
    }
    if (Test-Path -LiteralPath $repoDir) {
        Remove-ArchMcpDirectorySafe -TargetPath $repoDir
        Write-ArchOk "Removed local 3ds Max MCP server directory: $repoDir"
    }

    Write-Host ''
    Write-Host "3DS MAX $maxYear MCP DISABLED AND UNINSTALLED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Cyan
    Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0
}

if ($Action -eq 'Verify') {
    Write-ArchStep "Verifying 3ds Max $maxYear MCP installation and live bridge status"
    $filesOk = (Test-Path -LiteralPath (Join-Path $repoDir 'pyproject.toml')) -and
               (Test-Path -LiteralPath $maxConfigIni)
    if (-not $filesOk) {
        throw "3ds Max MCP files or mcp_config.ini are missing. Click 'Install & connect' or 'Repair' first."
    }
    Write-ArchOk "3ds Max MCP source and configuration verified at: $repoDir"

    if (Test-3dsMaxBridgeActive) {
        Write-ArchOk 'LIVE VERIFIED: 3ds Max bridge (Named Pipe or TCP 8765 listener) is active.'
        Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0
    } else {
        Write-ArchWarn "STATIC FILES INSTALLED, LIVE 3DS MAX BRIDGE INACTIVE: No running 3ds Max $maxYear MCP pipe or TCP port 8765 detected."
        Write-Host "Open Autodesk 3ds Max $maxYear to load the startup bridge, then run Verify again." -ForegroundColor Yellow
        Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 2
    }
}

$tmp = Join-Path $env:TEMP ('ArchMCP-3dsMax-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Write-ArchStep 'Downloading and validating cl0nazepamm/3dsmax-mcp from GitHub'
    $dl = Download-GitHubRepositorySource -OwnerRepo 'cl0nazepamm/3dsmax-mcp' `
        -DestinationDir $repoDir `
        -RequiredFiles @('pyproject.toml', 'install.py', 'maxmcp') `
        -TempDir $tmp
    if ($dl.BackupPath) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $dl.BackupPath; Target = $repoDir }
    }
    Write-ArchOk "Downloaded and verified 3dsmax-mcp ($($dl.VersionLabel))."

    Write-ArchStep 'Preparing user-local uv package manager'
    $uvInfo = Ensure-UvExecutable -TempDir $tmp
    $uvExe = $uvInfo.UvPath
    Write-ArchOk "uv available at: $uvExe"

    Write-ArchStep 'Resolving Python dependencies via uv sync'
    Invoke-ArchMcpUvSync -UvExe $uvExe -ProjectDir $repoDir

    Write-ArchStep 'Configuring %LOCALAPPDATA%\3dsmax-mcp\mcp_config.ini (Safe Mode enabled)'
    $iniBackup = Set-IniSectionKeyValues -IniPath $maxConfigIni -Section 'mcp' -KeyValues @{
        'safe_mode'                 = 'true'
        'tool_profile'              = 'full'
        'tcp_idle_poll_interval_ms' = '1000'
    }
    if ($iniBackup) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $iniBackup; Target = $maxConfigIni }
    }
    Write-ArchOk "Saved configuration: $maxConfigIni"

    if ($maxYear -ge 2023) {
        Write-ArchStep 'Running upstream bundle deployment (install.py --tool-profile full --skip-skill)'
        try {
            $instRes = Invoke-ArchMcpNativeCommand -FilePath $uvExe -ArgumentList @('run', '--directory', $repoDir, 'python', 'install.py', '--tool-profile', 'full', '--skip-skill')
            if ($instRes.ExitCode -eq 0) {
                Write-ArchOk 'Upstream install.py deployed 3ds Max 2023+ bridge bundle.'
            } else {
                Write-ArchWarn "install.py returned exit code $($instRes.ExitCode); deploying user-level startup MAXScript fallback."
            }
        } catch {
            Write-ArchWarn "install.py encountered a non-fatal warning: $($_.Exception.Message)"
        }
    } else {
        Write-ArchStep "Configuring MAXScript TCP Listener mode for 3ds Max $maxYear (2021-2022 compatibility)"
    }

    # Always deploy the MAXScript listener to the per-user 3ds Max startup folder so 2021-2027 all auto-start cleanly
    $repoListenerScript = Join-Path $repoDir 'maxscript\mcp_server.ms'
    if (Test-Path -LiteralPath $repoListenerScript -PathType Leaf) {
        $msBackup = Backup-ArchMcpPath -TargetPath $userStartupScriptFile
        if ($msBackup) {
            $script:RollbackStack += [pscustomobject]@{ Backup = $msBackup; Target = $userStartupScriptFile }
        }
        Copy-Item -LiteralPath $repoListenerScript -Destination $userStartupScriptFile -Force
        Write-ArchOk "Deployed MAXScript startup listener to: $userStartupScriptFile"
    }
    $repoAutoStart = Join-Path $repoDir 'maxscript\startup\mcp_autostart.ms'
    if (Test-Path -LiteralPath $repoAutoStart -PathType Leaf) {
        Copy-Item -LiteralPath $repoAutoStart -Destination (Join-Path $userScriptsStartup 'mcp_autostart.ms') -Force
    }

    Write-ArchStep "Registering '3dsmax-mcp' server with $AgentName"
    $reg = Register-ArchMcpWithAgent -AgentName $AgentName -ServerName '3dsmax-mcp' -Command $uvExe `
        -Arguments @('run', '--directory', $repoDir, '3dsmax-mcp') `
        -EnvironmentVariables @{ 'MCP_TOOL_PROFILE' = 'full' }
    if ($reg.BackupPath) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $reg.BackupPath; Target = $reg.ConfigPath }
    }
    Write-ArchOk "Registered '3dsmax-mcp' in $($reg.Agent): $($reg.ConfigPath)"

    if (Test-3dsMaxBridgeActive) {
        Write-Host ''
        Write-Host 'INSTALLATION AND LIVE 3DS MAX BRIDGE CHECK SUCCEEDED (STATUS = VERIFIED)' -ForegroundColor Green
    } else {
        Write-Host ''
        Write-ArchWarn "FILES & AGENT CONFIGURATION COMPLETED (STATUS = INSTALLED / AWAITING 3DS MAX $maxYear RESTART)"
        Write-Host "Restart Autodesk 3ds Max $maxYear so the bridge / MAXScript listener starts automatically."
    }
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Cyan
}
finally {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0

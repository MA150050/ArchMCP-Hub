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

$logPath = Start-ArchMcpLog -Prefix "rhino-$($Action.ToLowerInvariant())"
$script:RollbackStack = @()

trap {
    Write-Host ''
    Write-ArchErr "RHINO MCP $($Action.ToUpperInvariant()) FAILED: $($_.Exception.Message)"
    if ($script:RollbackStack.Count -gt 0) {
        Write-ArchWarn 'Executing automatic rollback of modified configurations...'
        for ($i = $script:RollbackStack.Count - 1; $i -ge 0; $i--) {
            $rb = $script:RollbackStack[$i]
            try { Restore-ArchMcpBackup -BackupPath $rb.Backup -TargetPath $rb.Target } catch { }
        }
    }
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Yellow
    Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 1
}

function Find-RhinoYakExe {
    param([string]$HintDir, [int]$MajorVer)
    $candidates = @()
    if ($HintDir) {
        $candidates += (Join-Path $HintDir 'System\yak.exe')
        $candidates += (Join-Path $HintDir 'yak.exe')
    }
    $candidates += @(
        (Join-Path $env:ProgramFiles "Rhino $MajorVer\System\yak.exe"),
        (Join-Path $env:ProgramFiles "Rhinoceros $MajorVer\System\yak.exe"),
        (Join-Path $env:ProgramFiles 'Rhino 8\System\yak.exe'),
        (Join-Path $env:ProgramFiles 'Rhino 7\System\yak.exe')
    )
    foreach ($c in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    return $null
}

$majorMatch = [regex]::Match($HostVersion, '(?<!\d)([7-9]|\d{2})(?:\.\d+)?')
$majorVer = if ($majorMatch.Success) { [int]$majorMatch.Groups[1].Value } else { 0 }
if ($majorVer -lt 7) {
    throw "This integration requires Rhinoceros 7 or 8 (detected: $HostVersion)."
}

$root = Join-Path (Get-ArchMcpRootDataDir) 'Integrations'
$rhino7RepoDir = Join-Path $root 'rhino7-mcp'
$rhinoUserScriptsDir = Join-Path $env:APPDATA "McNeel\Rhinoceros\$majorVer.0\scripts"
$rhino7BridgeScript = Join-Path $rhinoUserScriptsDir 'rhino_mcp_bridge.py'
New-Item -ItemType Directory -Force -Path $root, $rhinoUserScriptsDir | Out-Null

Write-Host "ArchMCP Hub - Rhino MCP ($Action) for $AgentName" -ForegroundColor Cyan
Write-Host "Target Rhino : $HostVersion (Major Version: $majorVer)"
if ($majorVer -ge 8) {
    Write-Host 'Upstream     : https://github.com/jingcheng-chen/rhinomcp (Rhino 8 Yak + TCP 1999)'
} else {
    Write-Host 'Upstream     : https://github.com/reer-ide/rhino_mcp (Rhino 7 Python TCP Bridge)'
}

if ($Action -eq 'Uninstall') {
    Write-ArchStep "Disabling and uninstalling Rhino $majorVer MCP integration"
    Unregister-ArchMcpFromAgent -AgentName $AgentName -ServerName 'rhino' -AllExistingAgents | Out-Null
    Stop-ArchMcpIntegrationProcesses -IntegrationDir $rhino7RepoDir

    if ($majorVer -ge 8) {
        $yakExe = Find-RhinoYakExe -HintDir $InstallPath -MajorVer $majorVer
        if ($yakExe) {
            try {
                Invoke-ArchMcpNativeCommand -FilePath $yakExe -ArgumentList @('uninstall', 'rhinomcp') | Out-Null
                Write-ArchOk 'Uninstalled rhinomcp via Rhino 8 Yak CLI.'
            } catch { }
        }
        $yakPkgDir = Join-Path $env:APPDATA "McNeel\Rhinoceros\packages\$majorVer.0\rhinomcp"
        if (Test-Path -LiteralPath $yakPkgDir) {
            Remove-ArchMcpDirectorySafe -TargetPath $yakPkgDir
            Write-ArchOk "Removed Rhino $majorVer Yak package folder: $yakPkgDir"
        }
        $uvExeLocal = Join-Path (Get-ArchMcpRootDataDir) 'Tools\uv\uv.exe'
        if (Test-Path -LiteralPath $uvExeLocal -PathType Leaf) {
            try { Invoke-ArchMcpNativeCommand -FilePath $uvExeLocal -ArgumentList @('tool', 'uninstall', 'rhinomcp') | Out-Null } catch { }
        }
    }

    if (Test-Path -LiteralPath $rhino7BridgeScript) {
        Remove-Item -LiteralPath $rhino7BridgeScript -Force -ErrorAction SilentlyContinue
        Write-ArchOk "Removed Rhino Python bridge script: $rhino7BridgeScript"
    }
    Get-ChildItem -LiteralPath $rhinoUserScriptsDir -Filter 'rhino_mcp_bridge.py.backup-*' -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }
    if ($majorVer -lt 8 -and (Test-Path -LiteralPath $rhino7RepoDir)) {
        Remove-ArchMcpDirectorySafe -TargetPath $rhino7RepoDir
        Write-ArchOk "Removed Rhino 7 MCP server directory: $rhino7RepoDir"
    }

    Write-Host ''
    Write-Host "RHINO $majorVer MCP DISABLED AND UNINSTALLED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Cyan
    Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0
}

if ($Action -eq 'Verify') {
    Write-ArchStep "Verifying Rhino $majorVer MCP installation and live TCP bridge"
    if ($majorVer -ge 8) {
        $yakExe = Find-RhinoYakExe -HintDir $InstallPath -MajorVer $majorVer
        $yakOk = $false
        if ($yakExe) {
            $yakRes = Invoke-ArchMcpNativeCommand -FilePath $yakExe -ArgumentList @('list')
            $yakList = $yakRes.Output
            if ($yakList -match '(?i)rhinomcp') { $yakOk = $true }
        }
        $scriptOk = Test-Path -LiteralPath $rhino7BridgeScript -PathType Leaf
        if (-not $yakOk -and -not $scriptOk) {
            throw "Rhino 8 MCP plugin/script is not installed yet. Click 'Install & connect' or 'Repair' first."
        }
        Write-ArchOk 'Rhino 8 MCP plugin/bridge files verified.'
    } else {
        $filesOk = (Test-Path -LiteralPath $rhino7BridgeScript -PathType Leaf) -and
                   (Test-Path -LiteralPath (Join-Path $rhino7RepoDir 'pyproject.toml') -PathType Leaf)
        if (-not $filesOk) {
            throw "Rhino 7 MCP bridge files are missing at $rhino7BridgeScript. Click 'Install & connect' or 'Repair' first."
        }
        Write-ArchOk "Rhino 7 Python bridge verified at: $rhino7BridgeScript"
    }

    $port1999 = Test-TcpPortListening -HostAddress '127.0.0.1' -Port 1999 -TimeoutMs 2000
    $port9877 = Test-TcpPortListening -HostAddress '127.0.0.1' -Port 9877 -TimeoutMs 1500
    if ($port1999 -or $port9877) {
        Write-ArchOk 'LIVE VERIFIED: Rhino TCP bridge is active and accepting connections.'
        Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0
    } else {
        Write-ArchWarn 'STATIC PLUGIN INSTALLED, LIVE BRIDGE INACTIVE: Rhino TCP listener is not currently running.'
        if ($majorVer -ge 8) {
            Write-Host 'Open Rhino 8 and run command: mcpstart' -ForegroundColor Yellow
        } else {
            Write-Host "Open Rhino 7 -> Tools -> PythonScript -> Run -> select: $rhino7BridgeScript" -ForegroundColor Yellow
        }
        Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 2
    }
}

$tmp = Join-Path $env:TEMP ('ArchMCP-Rhino-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Write-ArchStep 'Preparing user-local uv / uvx runtime'
    $uvInfo = Ensure-UvExecutable -TempDir $tmp
    $uvxExe = $uvInfo.UvxPath
    $uvExe = $uvInfo.UvPath
    Write-ArchOk "uv available at: $uvExe"

    if ($majorVer -ge 8) {
        $yakExe = Find-RhinoYakExe -HintDir $InstallPath -MajorVer $majorVer
        if ($yakExe) {
            Write-ArchStep 'Installing/updating rhinomcp plugin via Rhino 8 Yak CLI'
            $yakInst = Invoke-ArchMcpNativeCommand -FilePath $yakExe -ArgumentList @('install', 'rhinomcp')
            if ($yakInst.ExitCode -ne 0) {
                Write-ArchWarn "Yak install returned code $($yakInst.ExitCode); continuing with Python server registration."
            } else {
                Write-ArchOk 'rhinomcp Yak plugin installed in Rhino 8.'
            }
        }
        Invoke-ArchMcpNativeCommand -FilePath $uvExe -ArgumentList @('tool', 'install', '--force', 'rhinomcp') | Out-Null

        $cmdToUse = $uvxExe
        $argsToUse = @('rhinomcp@latest')
        if ($uvxExe -ieq $uvExe) {
            $argsToUse = @('tool', 'run', 'rhinomcp@latest')
        }

        Write-ArchStep "Registering 'rhino' MCP server (Rhino 8) with $AgentName"
        $reg = Register-ArchMcpWithAgent -AgentName $AgentName -ServerName 'rhino' -Command $cmdToUse `
            -Arguments $argsToUse `
            -EnvironmentVariables @{ 'RHINO_MCP_HOST' = '127.0.0.1'; 'RHINO_MCP_PORT' = '1999' }
        if ($reg.BackupPath) {
            $script:RollbackStack += [pscustomobject]@{ Backup = $reg.BackupPath; Target = $reg.ConfigPath }
        }
        Write-ArchOk "Registered 'rhino' MCP in $($reg.Agent): $($reg.ConfigPath)"
    }
    else {
        Write-ArchStep 'Downloading and validating reer-ide/rhino_mcp for Rhino 7'
        $dl = Download-GitHubRepositorySource -OwnerRepo 'reer-ide/rhino_mcp' `
            -DestinationDir $rhino7RepoDir `
            -RequiredFiles @('pyproject.toml', 'rhino_script.py') `
            -TempDir $tmp
        if ($dl.BackupPath) {
            $script:RollbackStack += [pscustomobject]@{ Backup = $dl.BackupPath; Target = $rhino7RepoDir }
        }
        Write-ArchOk "Downloaded and verified reer-ide/rhino_mcp ($($dl.VersionLabel))."

        Write-ArchStep 'Resolving Python dependencies for Rhino 7 MCP server'
        # Upstream pins anyio<4 (unsatisfiable with any mcp 1.x) and ships a stale uv.lock, so `uv sync` / `uv run` cannot work.
        $rhinoModern = ($AgentName -match '(?i)antigravity')
        if ($rhinoModern) {
            # Antigravity speaks MCP 2026-07-28 -> MCP SDK 2.x venv + compat entry (unmodified upstream main.py).
            $rhinoPy = Initialize-ArchMcpPipEnv -UvExe $uvExe -ProjectDir $rhino7RepoDir -EnvName '.venv-modern' -PythonVersion '3.12' -OverrideLines @('anyio>=4.5')
            $shimSrc = Join-Path $PSScriptRoot 'shims\archmcp_mcp2_entry.py'
            if (-not (Test-Path -LiteralPath $shimSrc -PathType Leaf)) { throw "Missing compatibility entry script: $shimSrc" }
            $shimDir = Join-Path $root 'Shims'
            New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
            $shimDst = Join-Path $shimDir 'archmcp_mcp2_entry.py'
            Copy-Item -LiteralPath $shimSrc -Destination $shimDst -Force
            $rhinoCmd = $rhinoPy
            $rhinoArgs = @($shimDst, (Join-Path $rhino7RepoDir 'main.py'))
        } else {
            $rhinoPy = Initialize-ArchMcpPipEnv -UvExe $uvExe -ProjectDir $rhino7RepoDir -EnvName '.venv' -PythonVersion '3.12' -OverrideLines @('anyio>=4.5', 'mcp[cli]>=1.3.0,<2')
            $rhinoCmd = $rhinoPy
            $rhinoArgs = @((Join-Path $rhino7RepoDir 'main.py'))
        }

        Write-ArchStep "Deploying Rhino 7 Python socket script to $rhino7BridgeScript"
        $scriptBackup = Backup-ArchMcpPath -TargetPath $rhino7BridgeScript
        if ($scriptBackup) {
            $script:RollbackStack += [pscustomobject]@{ Backup = $scriptBackup; Target = $rhino7BridgeScript }
        }
        Copy-Item -LiteralPath (Join-Path $rhino7RepoDir 'rhino_script.py') -Destination $rhino7BridgeScript -Force
        Write-ArchOk "Deployed Rhino 7 bridge script: $rhino7BridgeScript"

        Write-ArchStep "Registering 'rhino' MCP server (Rhino 7) with $AgentName"
        $reg = Register-ArchMcpWithAgent -AgentName $AgentName -ServerName 'rhino' -Command $rhinoCmd `
            -Arguments $rhinoArgs `
            -EnvironmentVariables @{ 'RHINO_MCP_HOST' = '127.0.0.1' }
        if ($reg.BackupPath) {
            $script:RollbackStack += [pscustomobject]@{ Backup = $reg.BackupPath; Target = $reg.ConfigPath }
        }
        Write-ArchOk "Registered 'rhino' MCP in $($reg.Agent): $($reg.ConfigPath)"
    }

    Write-ArchStep 'Checking live Rhino TCP bridge'
    $live = (Test-TcpPortListening -HostAddress '127.0.0.1' -Port 1999 -TimeoutMs 2000) -or
            (Test-TcpPortListening -HostAddress '127.0.0.1' -Port 9877 -TimeoutMs 1500)
    if ($live) {
        Write-Host ''
        Write-Host 'INSTALLATION AND LIVE RHINO BRIDGE CHECK SUCCEEDED (STATUS = VERIFIED)' -ForegroundColor Green
    } else {
        Write-Host ''
        Write-ArchWarn "PLUGIN & AGENT CONFIGURATION COMPLETED (STATUS = INSTALLED / AWAITING RHINO $majorVer START)"
        if ($majorVer -ge 8) {
            Write-Host 'To activate the live connection, open Rhinoceros 8 and type in the command line: mcpstart'
        } else {
            Write-Host "To activate the live connection in Rhino 7, open Tools -> PythonScript -> Run and select: $rhino7BridgeScript"
        }
    }
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Cyan
}
finally {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0

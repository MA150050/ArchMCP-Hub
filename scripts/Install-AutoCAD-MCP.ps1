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

$logPath = Start-ArchMcpLog -Prefix "autocad-$($Action.ToLowerInvariant())"
$script:RollbackStack = @()

trap {
    Write-Host ''
    Write-ArchErr "AUTOCAD MCP $($Action.ToUpperInvariant()) FAILED: $($_.Exception.Message)"
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
    throw "This integration supports Autodesk AutoCAD 2021-2027 only. Detected: $HostVersion"
}

$root = Join-Path (Get-ArchMcpRootDataDir) 'Integrations'
$repoDir = Join-Path $root 'autocad-mcp'
$allowedDocsDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AutoCAD'
New-Item -ItemType Directory -Force -Path $root, $allowedDocsDir | Out-Null

Write-Host "ArchMCP Hub - AutoCAD MCP Pro ($Action) for $AgentName" -ForegroundColor Cyan
Write-Host "Target AutoCAD: $HostVersion (2021-2027 supported)"
Write-Host 'Upstream      : https://github.com/U-C4N/Autocad-MCP (MIT)'

function Test-AutoCadLiveCom {
    try {
        $proc = Get-Process -Name 'acad' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $proc) { return $false }
        $acadObj = [System.Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application')
        return ($null -ne $acadObj)
    } catch {
        return $false
    }
}

if ($Action -eq 'Uninstall') {
    Write-ArchStep "Disabling and uninstalling AutoCAD MCP integration for $HostVersion"
    Unregister-ArchMcpFromAgent -AgentName $AgentName -ServerName 'autocad' -AllExistingAgents | Out-Null
    Stop-ArchMcpIntegrationProcesses -IntegrationDir $repoDir

    if (Test-Path -LiteralPath $repoDir) {
        Remove-ArchMcpDirectorySafe -TargetPath $repoDir
        Write-ArchOk "Removed local AutoCAD MCP server directory: $repoDir"
    }

    Write-Host ''
    Write-Host 'AUTOCAD MCP DISABLED AND UNINSTALLED SUCCESSFULLY' -ForegroundColor Green
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Cyan
    Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0
}

if ($Action -eq 'Verify') {
    Write-ArchStep 'Verifying AutoCAD MCP installation and live COM status'
    $filesOk = (Test-Path -LiteralPath (Join-Path $repoDir 'pyproject.toml')) -and
               (Test-Path -LiteralPath (Join-Path $repoDir 'server.py'))
    if (-not $filesOk) {
        throw "AutoCAD MCP files are missing at $repoDir. Click 'Install & connect' or 'Repair' first."
    }
    Write-ArchOk "AutoCAD MCP source verified at: $repoDir"

    if (Test-AutoCadLiveCom) {
        Write-ArchOk 'LIVE VERIFIED: Active AutoCAD COM instance (AutoCAD.Application) is running and reachable.'
        Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0
    } else {
        Write-ArchWarn 'STATIC FILES & HEADLESS ENGINE READY, LIVE AUTOCAD COM INACTIVE: AutoCAD is not currently running.'
        Write-Host 'Note: Headless DXF tools work immediately; live DWG COM control requires AutoCAD to be open.' -ForegroundColor Yellow
        Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 2
    }
}

$tmp = Join-Path $env:TEMP ('ArchMCP-AutoCAD-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Write-ArchStep 'Downloading and validating U-C4N/Autocad-MCP from GitHub'
    $dl = Download-GitHubRepositorySource -OwnerRepo 'U-C4N/Autocad-MCP' `
        -DestinationDir $repoDir `
        -RequiredFiles @('pyproject.toml', 'server.py', 'config.py') `
        -TempDir $tmp
    if ($dl.BackupPath) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $dl.BackupPath; Target = $repoDir }
    }
    Write-ArchOk "Downloaded and verified U-C4N/Autocad-MCP ($($dl.VersionLabel))."

    Write-ArchStep 'Preparing user-local uv package manager'
    $uvInfo = Ensure-UvExecutable -TempDir $tmp
    $uvExe = $uvInfo.UvPath
    Write-ArchOk "uv available at: $uvExe"

    Write-ArchStep 'Resolving Python dependencies (including COM & PDF extras) via uv sync'
    Invoke-ArchMcpUvSync -UvExe $uvExe -ProjectDir $repoDir -ExtraArgs @('--all-extras')

    Write-ArchStep "Registering 'autocad' MCP server with $AgentName"
    $reg = Register-ArchMcpWithAgent -AgentName $AgentName -ServerName 'autocad' -Command $uvExe `
        -Arguments @('run', '--directory', $repoDir, 'autocad-mcp') `
        -EnvironmentVariables @{
            'AUTOCAD_MCP_BACKEND'        = 'auto'
            'ALLOWED_PATHS'              = $allowedDocsDir
            'TOOL_PROFILE'               = 'full'
            'TOOL_PACKS'                 = 'core,arch,settings'
            'DANGEROUS_COMMANDS_ENABLED' = 'false'
        }
    if ($reg.BackupPath) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $reg.BackupPath; Target = $reg.ConfigPath }
    }
    Write-ArchOk "Registered 'autocad' MCP in $($reg.Agent): $($reg.ConfigPath)"

    if (Test-AutoCadLiveCom) {
        Write-Host ''
        Write-Host 'INSTALLATION AND LIVE AUTOCAD COM CHECK SUCCEEDED (STATUS = VERIFIED)' -ForegroundColor Green
    } else {
        Write-Host ''
        Write-ArchWarn 'INSTALLATION COMPLETED (STATUS = INSTALLED / HEADLESS READY, AWAITING LIVE AUTOCAD FOR COM)'
        Write-Host 'Headless DXF engine is ready now. Open AutoCAD with a drawing for live COM automation.'
    }
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Cyan
}
finally {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0

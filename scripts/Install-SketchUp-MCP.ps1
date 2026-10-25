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

$logPath = Start-ArchMcpLog -Prefix "sketchup-$($Action.ToLowerInvariant())"
$script:RollbackStack = @()

trap {
    Write-Host ''
    Write-ArchErr "SKETCHUP MCP $($Action.ToUpperInvariant()) FAILED: $($_.Exception.Message)"
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

function Resolve-SketchUpRubyPluginSource {
    param([Parameter(Mandatory = $true)] [string] $RepoDir)
    # Upstream mhyrr/sketchup-mcp and NeoNexAI/sketchup-mcp store the packaging layout inside `su_mcp/`:
    #   su_mcp/package.rb
    #   su_mcp/su_mcp.rb
    #   su_mcp/su_mcp/main.rb
    # Copying `su_mcp/` directly into `Plugins\su_mcp` nests `main.rb` at `Plugins\su_mcp\su_mcp\main.rb`,
    # which triggers SketchUp's `Error Loading File su_mcp/main: Could not find included file 'su_mcp/main'`.
    # This resolver normalizes both nested (`su_mcp/su_mcp/main.rb`) and flat (`su_mcp/main.rb`) layouts so
    # `Plugins\su_mcp.rb` and `Plugins\su_mcp\main.rb` are always deployed at the exact paths SketchUp requires.
    $nestedMainDir = Join-Path $RepoDir 'su_mcp\su_mcp'
    $flatMainDir   = Join-Path $RepoDir 'su_mcp'
    $nestedEntryRb = Join-Path $RepoDir 'su_mcp\su_mcp.rb'
    $rootEntryRb   = Join-Path $RepoDir 'su_mcp.rb'

    $resolvedSubSource = $null
    $resolvedEntryRb = $null

    if (Test-Path -LiteralPath (Join-Path $nestedMainDir 'main.rb') -PathType Leaf) {
        $resolvedSubSource = $nestedMainDir
        $resolvedEntryRb = if (Test-Path -LiteralPath $nestedEntryRb -PathType Leaf) { $nestedEntryRb } else { $rootEntryRb }
    } elseif (Test-Path -LiteralPath (Join-Path $flatMainDir 'main.rb') -PathType Leaf) {
        $resolvedSubSource = $flatMainDir
        $resolvedEntryRb = if (Test-Path -LiteralPath $rootEntryRb -PathType Leaf) { $rootEntryRb } else { $nestedEntryRb }
    } else {
        $foundMain = Get-ChildItem -LiteralPath $RepoDir -Filter 'main.rb' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $foundMain) {
            throw "Could not find SketchUp Ruby extension 'main.rb' inside downloaded repository '$RepoDir'."
        }
        $resolvedSubSource = $foundMain.DirectoryName
        $siblingRb = Join-Path (Split-Path -Parent $resolvedSubSource) 'su_mcp.rb'
        $resolvedEntryRb = if (Test-Path -LiteralPath $siblingRb -PathType Leaf) { $siblingRb } else { $rootEntryRb }
    }

    if (-not (Test-Path -LiteralPath $resolvedEntryRb -PathType Leaf)) {
        throw "Could not find SketchUp Ruby extension loader 'su_mcp.rb' inside '$RepoDir'."
    }

    return [pscustomobject]@{
        EntryRbPath = $resolvedEntryRb
        MainDirPath = $resolvedSubSource
    }
}

function Write-SketchUpMcpLauncherScript {
    param([Parameter(Mandatory = $true)] [string] $LauncherPath)
    $pyLines = @(
        '"""ArchMCP Hub - SketchUp MCP stdio server launcher."""',
        'import inspect',
        'import os',
        'import sys',
        '',
        'repo_dir = os.path.dirname(os.path.abspath(__file__))',
        'for rel in ("src", "."):',
        '    candidate = os.path.normpath(os.path.join(repo_dir, rel))',
        '    if os.path.isdir(candidate) and candidate not in sys.path:',
        '        sys.path.insert(0, candidate)',
        '',
        'try:',
        '    from mcp.server.fastmcp import FastMCP as _OrigFastMCP',
        '    _sig = inspect.signature(_OrigFastMCP.__init__)',
        '    if "description" not in _sig.parameters and not any(',
        '        p.kind == inspect.Parameter.VAR_KEYWORD for p in _sig.parameters.values()',
        '    ):',
        '        _orig_init = _OrigFastMCP.__init__',
        '',
        '        def _patched_init(self, *args, **kwargs):',
        '            kwargs.pop("description", None)',
        '            return _orig_init(self, *args, **kwargs)',
        '',
        '        _OrigFastMCP.__init__ = _patched_init',
        'except Exception:',
        '    pass',
        '',
        'try:',
        '    from sketchup_mcp.server import main',
        'except ImportError:',
        '    from server import main  # type: ignore',
        '',
        'if __name__ == "__main__":',
        '    main()'
    )
    Write-Utf8NoBomFile -FilePath $LauncherPath -Content ($pyLines -join "`n")
}

$yearMatch = [regex]::Match($HostVersion, '\b(20\d{2})\b')
if (-not $yearMatch.Success -or [int]$yearMatch.Groups[1].Value -lt 2021) {
    throw "This integration supports SketchUp 2021-2026 only. Detected: $HostVersion"
}
$suYear = $yearMatch.Groups[1].Value

$root = Join-Path (Get-ArchMcpRootDataDir) 'Integrations'
$repoDir = Join-Path $root 'sketchup-mcp'
$suPluginsDir = Join-Path $env:APPDATA "SketchUp\SketchUp $suYear\SketchUp\Plugins"
$suEntryRb = Join-Path $suPluginsDir 'su_mcp.rb'
$suSubDir = Join-Path $suPluginsDir 'su_mcp'
$suMainRb = Join-Path $suSubDir 'main.rb'
$launchScript = Join-Path $repoDir 'archmcp_sketchup_server.py'
New-Item -ItemType Directory -Force -Path $root, $suPluginsDir | Out-Null

Write-Host "ArchMCP Hub - SketchUp MCP Hardened ($Action) for $AgentName" -ForegroundColor Cyan
Write-Host "Target SketchUp : SketchUp $suYear ($HostVersion)"
Write-Host "Plugins Folder  : $suPluginsDir"
Write-Host 'Upstream        : https://github.com/NeoNexAI/sketchup-mcp (MIT, hardened no-eval fork of mhyrr/sketchup-mcp)'

if ($Action -eq 'Uninstall') {
    Write-ArchStep "Disabling and uninstalling SketchUp $suYear MCP integration"
    Unregister-ArchMcpFromAgent -AgentName $AgentName -ServerName 'sketchup' -AllExistingAgents | Out-Null
    Stop-ArchMcpIntegrationProcesses -IntegrationDir $repoDir

    if (Test-Path -LiteralPath $suEntryRb) {
        Remove-Item -LiteralPath $suEntryRb -Force -ErrorAction SilentlyContinue
        Write-ArchOk "Removed SketchUp Ruby loader: $suEntryRb"
    }
    if (Test-Path -LiteralPath $suSubDir) {
        Remove-Item -LiteralPath $suSubDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-ArchOk "Removed SketchUp Ruby extension folder: $suSubDir"
    }
    # Clean any stray .backup-* items inside SketchUp Plugins folder
    Get-ChildItem -LiteralPath $suPluginsDir -Filter 'su_mcp*.backup-*' -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    $otherSuPlugins = $false
    foreach ($yr in 2021..2026) {
        $otherRb = Join-Path $env:APPDATA "SketchUp\SketchUp $yr\SketchUp\Plugins\su_mcp.rb"
        if (Test-Path -LiteralPath $otherRb -PathType Leaf) {
            $otherSuPlugins = $true
            break
        }
    }
    if (-not $otherSuPlugins) {
        Remove-ArchMcpDirectorySafe -TargetPath $repoDir
        Write-ArchOk "Removed local SketchUp MCP server files: $repoDir"
    }

    Write-Host ''
    Write-Host "SKETCHUP $suYear MCP DISABLED AND UNINSTALLED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Cyan
    Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0
}

if ($Action -eq 'Verify') {
    Write-ArchStep 'Verifying SketchUp Ruby extension (su_mcp.rb + su_mcp/main.rb) and live TCP socket (127.0.0.1:9876)'
    $filesOk = (Test-Path -LiteralPath (Join-Path $repoDir 'pyproject.toml') -PathType Leaf) -and
               (Test-Path -LiteralPath $suEntryRb -PathType Leaf) -and
               (Test-Path -LiteralPath $suMainRb -PathType Leaf)
    if (-not $filesOk) {
        throw "SketchUp MCP files or Ruby plugin ($suEntryRb and $suMainRb) are missing or incomplete. Click 'Install & connect' or 'Repair' first."
    }
    Write-ArchOk "SketchUp Ruby extension verified at: $suEntryRb and $suMainRb"

    if (Test-TcpPortListening -HostAddress '127.0.0.1' -Port 9876 -TimeoutMs 2500) {
        Write-ArchOk 'LIVE VERIFIED: SketchUp MCP TCP server on 127.0.0.1:9876 is active and listening.'
        Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0
    } else {
        Write-ArchWarn 'STATIC EXTENSION INSTALLED, LIVE SERVER INACTIVE: TCP port 127.0.0.1:9876 is not listening.'
        Write-Host "Open SketchUp $suYear and select menu: Extensions -> SketchUp MCP -> Start Server" -ForegroundColor Yellow
        Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 2
    }
}

$tmp = Join-Path $env:TEMP ('ArchMCP-SketchUp-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Write-ArchStep 'Downloading and validating NeoNexAI/sketchup-mcp (with mhyrr/sketchup-mcp fallback)'
    $dl = $null
    $forceDl = ($Action -eq 'Repair')
    try {
        $dl = Download-GitHubRepositorySource -OwnerRepo 'NeoNexAI/sketchup-mcp' `
            -DestinationDir $repoDir `
            -RequiredFiles @('pyproject.toml', 'su_mcp') `
            -TempDir $tmp `
            -ForceDownload:$forceDl
    } catch {
        Write-ArchWarn "NeoNexAI/sketchup-mcp download failed ($($_.Exception.Message)); falling back to upstream mhyrr/sketchup-mcp..."
        $dl = Download-GitHubRepositorySource -OwnerRepo 'mhyrr/sketchup-mcp' `
            -DestinationDir $repoDir `
            -RequiredFiles @('pyproject.toml', 'su_mcp') `
            -TempDir $tmp `
            -ForceDownload:$forceDl
    }
    if ($dl.BackupPath) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $dl.BackupPath; Target = $repoDir }
    }
    Write-ArchOk "Downloaded and verified $($dl.Repository) ($($dl.VersionLabel))."

    Write-ArchStep 'Preparing user-local uv package manager'
    $uvInfo = Ensure-UvExecutable -TempDir $tmp
    $uvExe = $uvInfo.UvPath
    Write-ArchOk "uv available at: $uvExe"

    Write-ArchStep 'Resolving Python dependencies in isolated Python 3.12 virtual environment'
    # Avoid `uv run neonexai-sketchup-mcp` at runtime (which fails with exit code 2 'Failed to spawn: neonexai-sketchup-mcp'
    # when the console script name differs in pyproject.toml or is not on PATH, and avoids mcp 2.x breaking FastMCP v1 imports).
    $suModern = ($AgentName -match '(?i)antigravity')
    if ($suModern) {
        $suPy = Initialize-ArchMcpPipEnv -UvExe $uvExe -ProjectDir $repoDir -EnvName '.venv-modern' -PythonVersion '3.12' -OverrideLines @('anyio>=4.5')
    } else {
        $suPy = Initialize-ArchMcpPipEnv -UvExe $uvExe -ProjectDir $repoDir -EnvName '.venv' -PythonVersion '3.12' -OverrideLines @('anyio>=4.5', 'mcp[cli]>=1.3.0,<2')
    }
    Invoke-ArchMcpNativeCommand -FilePath $uvExe -ArgumentList @('pip', 'install', '--python', $suPy, '--no-deps', '-e', $repoDir) | Out-Null
    Write-SketchUpMcpLauncherScript -LauncherPath $launchScript
    Write-ArchOk "Prepared SketchUp MCP Python launcher: $launchScript"

    if ($suModern) {
        $shimSrc = Join-Path $PSScriptRoot 'shims\archmcp_mcp2_entry.py'
        if (-not (Test-Path -LiteralPath $shimSrc -PathType Leaf)) { throw "Missing compatibility entry script: $shimSrc" }
        $shimDir = Join-Path $root 'Shims'
        New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
        $shimDst = Join-Path $shimDir 'archmcp_mcp2_entry.py'
        Copy-Item -LiteralPath $shimSrc -Destination $shimDst -Force
        $suCmd = $suPy
        $suArgs = @($shimDst, $launchScript)
    } else {
        $suCmd = $suPy
        $suArgs = @($launchScript)
    }

    Write-ArchStep "Deploying SketchUp Ruby extension (su_mcp.rb + su_mcp/main.rb) to $suPluginsDir"
    $pluginSrc = Resolve-SketchUpRubyPluginSource -RepoDir $repoDir

    # Remove any stray .backup-* files inside SketchUp Plugins folder so SketchUp never attempts to load backup files
    Get-ChildItem -LiteralPath $suPluginsDir -Filter 'su_mcp*.backup-*' -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Copy-Item -LiteralPath $pluginSrc.EntryRbPath -Destination $suEntryRb -Force
    if (Test-Path -LiteralPath $suSubDir) {
        Remove-Item -LiteralPath $suSubDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $suSubDir | Out-Null
    & robocopy.exe $pluginSrc.MainDirPath $suSubDir /MIR /XF 'package.rb' 'su_mcp.rb' /XD 'su_mcp' /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
    $global:LASTEXITCODE = 0

    if (-not (Test-Path -LiteralPath $suEntryRb -PathType Leaf) -or -not (Test-Path -LiteralPath $suMainRb -PathType Leaf)) {
        throw "SketchUp Ruby extension verification failed: '$suEntryRb' or '$suMainRb' was not deployed properly."
    }
    Write-ArchOk "Deployed su_mcp.rb and su_mcp/main.rb to $suPluginsDir"

    $suEnvVars = @{
        'SKETCHUP_MCP_HOST'    = '127.0.0.1'
        'SKETCHUP_MCP_PORT'    = '9876'
        'SKETCHUP_MCP_TIMEOUT' = '30'
        'PYTHONUNBUFFERED'     = '1'
        'PYTHONUTF8'           = '1'
    }

    Write-ArchStep 'Verifying SketchUp MCP server stdio handshake (initialize + tools/list)'
    $hs = Test-ArchMcpStdioHandshake -Command $suCmd -Arguments $suArgs -EnvironmentVariables $suEnvVars -TimeoutSec 60
    if ($hs.Error) {
        throw "SketchUp MCP server failed stdio handshake check: $($hs.Error) | stderr: $($hs.StderrTail)"
    }
    Write-ArchOk "SketchUp MCP server handshake verified in $($hs.Seconds)s ($($hs.ToolCount) tools discovered)."

    Write-ArchStep "Registering 'sketchup' MCP server with $AgentName"
    $reg = Register-ArchMcpWithAgent -AgentName $AgentName -ServerName 'sketchup' -Command $suCmd `
        -Arguments $suArgs `
        -EnvironmentVariables $suEnvVars
    if ($reg.BackupPath) {
        $script:RollbackStack += [pscustomobject]@{ Backup = $reg.BackupPath; Target = $reg.ConfigPath }
    }
    Write-ArchOk "Registered 'sketchup' MCP in $($reg.Agent): $($reg.ConfigPath)"

    if (Test-TcpPortListening -HostAddress '127.0.0.1' -Port 9876 -TimeoutMs 2500) {
        Write-Host ''
        Write-Host 'INSTALLATION AND LIVE SKETCHUP SERVER CHECK SUCCEEDED (STATUS = VERIFIED)' -ForegroundColor Green
    } else {
        Write-Host ''
        Write-ArchWarn 'EXTENSION & AGENT CONFIGURATION COMPLETED (STATUS = INSTALLED / AWAITING SKETCHUP SERVER START)'
        Write-Host "Restart SketchUp $suYear, then click: Extensions -> SketchUp MCP -> Start Server"
    }
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Cyan
}
finally {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Wait-ArchMcpWindowClose -NonInteractive:$NonInteractive -ExitCode 0

#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helper library for ArchMCP Hub installer, verifier, repair, and uninstall scripts.
    Strictly 7-bit ASCII clean for 100% compatibility with Windows PowerShell 5.1 and PowerShell 7+.
#>

function Invoke-ArchMcpNativeCommand {
    <#
    .SYNOPSIS
        Executes a native executable in Windows PowerShell 5.1 WITHOUT triggering a terminating NativeCommandError
        when the executable writes progress/status lines to stderr (such as uv, git, yak, pyrevit, or python).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath,
        [string[]] $ArgumentList = @()
    )
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $captured = ''
    $code = 0
    try {
        $rawOut = & $FilePath @ArgumentList 2>&1
        $code = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
        $captured = ($rawOut | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.Exception.Message
            } else {
                [string]$_
            }
        }) -join "`r`n"
    } finally {
        $ErrorActionPreference = $prevEap
        $global:LASTEXITCODE = 0
    }
    return [pscustomobject]@{
        ExitCode = $code
        Output   = $captured.Trim()
    }
}

function Initialize-ArchMcpTls {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor ([Net.SecurityProtocolType]::Tls13 -as [int])
    } catch {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
}

function Write-ArchStep([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-ArchOk([string]$Message)   { Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-ArchWarn([string]$Message) { Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-ArchErr([string]$Message)  { Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Wait-ArchMcpWindowClose {
    param(
        [switch] $NonInteractive,
        [int] $ExitCode = 0
    )
    try { Stop-Transcript | Out-Null } catch { }
    if (-not $NonInteractive) {
        Write-Host ''
        if ($ExitCode -eq 0) {
            Write-Host 'Operation finished. Press Enter to close this window...' -ForegroundColor Cyan
        } else {
            Write-Host "Operation finished with status code $ExitCode. Review the messages above, then press Enter to close..." -ForegroundColor Yellow
        }
        try { Read-Host | Out-Null } catch { }
    }
    exit $ExitCode
}

function Get-ArchMcpRootDataDir {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.local\share' }
    $dir = Join-Path $base 'ArchMCP Hub'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    return $dir
}

function Start-ArchMcpLog([string]$Prefix) {
    $logDir = Join-Path (Get-ArchMcpRootDataDir) 'Logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    $logPath = Join-Path $logDir ("$Prefix-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    try { Start-Transcript -LiteralPath $logPath -Append | Out-Null } catch { }
    return $logPath
}

function Expand-ArchMcpZipPayload {
    <#
    .SYNOPSIS
        Extracts a ZIP archive safely and returns the normalized payload root directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $ArchivePath,
        [Parameter(Mandatory = $true)] [string] $DestinationRoot,
        [string[]] $RequiredFiles = @()
    )
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Archive file does not exist: $ArchivePath"
    }
    if (Test-Path -LiteralPath $DestinationRoot) {
        Remove-Item -LiteralPath $DestinationRoot -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $DestinationRoot)
    } catch {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $DestinationRoot -Force
    }

    $topItems = @(Get-ChildItem -LiteralPath $DestinationRoot -Force | Where-Object { $_.Name -ne '__MACOSX' })
    if ($topItems.Count -eq 0) {
        throw "Extracted archive '$ArchivePath' is empty."
    }

    $payloadRoot = $DestinationRoot
    if ($topItems.Count -eq 1 -and $topItems[0].PSIsContainer) {
        $payloadRoot = $topItems[0].FullName
    }

    foreach ($req in $RequiredFiles) {
        $expectedPath = Join-Path $payloadRoot $req
        if (-not (Test-Path -LiteralPath $expectedPath)) {
            throw "Extracted archive did not contain expected path '$req' inside '$payloadRoot'."
        }
    }

    return $payloadRoot
}

function Backup-ArchMcpPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $TargetPath,
        [string[]] $ExcludeDirs = @('.venv', '.venv-modern', '.git', '__pycache__', '.pytest_cache')
    )
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        return $null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$TargetPath.backup-$stamp"
    if (Test-Path -LiteralPath $TargetPath -PathType Container) {
        New-Item -ItemType Directory -Force -Path $backupPath | Out-Null
        $xdArgs = @('/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1')
        if ($ExcludeDirs -and $ExcludeDirs.Count -gt 0) {
            $xdArgs += '/XD'
            $xdArgs += $ExcludeDirs
        }
        & robocopy.exe $TargetPath $backupPath @xdArgs | Out-Null
        $global:LASTEXITCODE = 0
    } else {
        Copy-Item -LiteralPath $TargetPath -Destination $backupPath -Force
    }
    return $backupPath
}

function Restore-ArchMcpBackup {
    [CmdletBinding()]
    param(
        [string] $BackupPath,
        [Parameter(Mandatory = $true)] [string] $TargetPath
    )
    if ($BackupPath -and (Test-Path -LiteralPath $BackupPath)) {
        if (Test-Path -LiteralPath $BackupPath -PathType Container) {
            New-Item -ItemType Directory -Force -Path $TargetPath | Out-Null
            & robocopy.exe $BackupPath $TargetPath /MIR /XD '.venv' '.venv-modern' /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
            $global:LASTEXITCODE = 0
            Remove-Item -LiteralPath $BackupPath -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Copy-Item -LiteralPath $BackupPath -Destination $TargetPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
        }
        Write-ArchWarn "Rolled back '$TargetPath' from backup '$BackupPath'."
    }
}

function Ensure-UvExecutable {
    [CmdletBinding()]
    param(
        [string] $TempDir
    )
    Initialize-ArchMcpTls
    $toolsDir = Join-Path (Get-ArchMcpRootDataDir) 'Tools\uv'
    New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
    $uvExe = Join-Path $toolsDir 'uv.exe'
    $uvxExe = Join-Path $toolsDir 'uvx.exe'

    if (Test-Path -LiteralPath $uvExe -PathType Leaf) {
        $resolvedUvx = $uvExe
        if (Test-Path -LiteralPath $uvxExe) { $resolvedUvx = $uvxExe }
        return [pscustomobject]@{ UvPath = $uvExe; UvxPath = $resolvedUvx }
    }

    $globalUv = Get-Command 'uv.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($globalUv -and (Test-Path -LiteralPath $globalUv.Source -PathType Leaf)) {
        Copy-Item -LiteralPath $globalUv.Source -Destination $uvExe -Force
        $siblingUvx = Join-Path (Split-Path -Parent $globalUv.Source) 'uvx.exe'
        if (Test-Path -LiteralPath $siblingUvx -PathType Leaf) {
            Copy-Item -LiteralPath $siblingUvx -Destination $uvxExe -Force
        }
        $resolvedUvx = $uvExe
        if (Test-Path -LiteralPath $uvxExe) { $resolvedUvx = $uvxExe }
        return [pscustomobject]@{ UvPath = $uvExe; UvxPath = $resolvedUvx }
    }

    $workTmp = if ($TempDir) { $TempDir } else { Join-Path $env:TEMP ('ArchMCP-uv-' + [guid]::NewGuid().ToString('N')) }
    New-Item -ItemType Directory -Force -Path $workTmp | Out-Null

    $headers = @{ 'User-Agent' = 'ArchMCP-Hub/1.0.0'; 'Accept' = 'application/vnd.github+json' }
    $uvRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/astral-sh/uv/releases/latest' -Headers $headers -UseBasicParsing
    $asset = $uvRelease.assets | Where-Object { $_.name -eq 'uv-x86_64-pc-windows-msvc.zip' } | Select-Object -First 1
    if (-not $asset) {
        throw 'Could not find the official Windows x64 uv release asset on GitHub.'
    }
    $uvZip = Join-Path $workTmp 'uv.zip'
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $uvZip -UseBasicParsing
    $uvExtract = Join-Path $workTmp 'uv-extract'
    Expand-ArchMcpZipPayload -ArchivePath $uvZip -DestinationRoot $uvExtract | Out-Null

    $foundUv = Get-ChildItem -LiteralPath $uvExtract -Filter 'uv.exe' -Recurse | Select-Object -First 1
    if (-not $foundUv) { throw 'uv.exe was not found in the downloaded official archive.' }
    Copy-Item -LiteralPath $foundUv.FullName -Destination $uvExe -Force

    $foundUvx = Get-ChildItem -LiteralPath $uvExtract -Filter 'uvx.exe' -Recurse | Select-Object -First 1
    if ($foundUvx) { Copy-Item -LiteralPath $foundUvx.FullName -Destination $uvxExe -Force }

    $resolvedUvx = $uvExe
    if (Test-Path -LiteralPath $uvxExe) { $resolvedUvx = $uvxExe }
    return [pscustomobject]@{ UvPath = $uvExe; UvxPath = $resolvedUvx }
}

function Download-GitHubRepositorySource {
    <#
    .SYNOPSIS
        Downloads or reuses a GitHub repository in DestinationDir.
        CRITICAL WINDOWS LOCK PROTECTION:
        When an MCP server is already running in OpenCode or Claude Desktop, `.venv\Scripts\python.exe` is locked by Windows.
        Instead of calling `Remove-Item -Recurse` on DestinationDir (which fails with 'Access to the path python.exe is denied'),
        this function syncs the downloaded source into DestinationDir via robocopy while EXCLUDING `.venv`!
        Also supports fast local reuse when switching between AI Agents (e.g., OpenCode -> Claude Desktop) if files are already valid.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $OwnerRepo,
        [Parameter(Mandatory = $true)] [string] $DestinationDir,
        [string[]] $RequiredFiles = @(),
        [string] $TempDir,
        [switch] $ForceDownload
    )

    # Check if DestinationDir already has all required source files (e.g., already installed for OpenCode and now registering for Claude Desktop)
    $alreadyComplete = (Test-Path -LiteralPath $DestinationDir -PathType Container)
    if ($alreadyComplete) {
        foreach ($req in $RequiredFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $DestinationDir $req))) {
                $alreadyComplete = $false
                break
            }
        }
    }
    if ($alreadyComplete -and -not $ForceDownload) {
        Write-ArchOk "Existing verified local source found at '$DestinationDir'; reusing without touching locked .venv processes."
        return [pscustomobject]@{
            Repository         = $OwnerRepo
            InstalledPath      = $DestinationDir
            BackupPath         = $null
            VersionLabel       = 'cached-local'
            UsedFallbackBranch = $false
            ArchiveSha256      = 'cachedlocal000000000000'
            ReusedExisting     = $true
        }
    }

    Initialize-ArchMcpTls
    $workTmp = if ($TempDir) { $TempDir } else { Join-Path $env:TEMP ('ArchMCP-src-' + [guid]::NewGuid().ToString('N')) }
    New-Item -ItemType Directory -Force -Path $workTmp | Out-Null

    $headers = @{ 'User-Agent' = 'ArchMCP-Hub/1.0.0'; 'Accept' = 'application/vnd.github+json' }
    $release = $null
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$OwnerRepo/releases/latest" -Headers $headers -UseBasicParsing -ErrorAction SilentlyContinue
    } catch {
        $release = $null
    }

    $usedFallbackBranch = $false
    $versionLabel = 'unknown'
    if ($release -and $release.zipball_url) {
        $archiveUrl = [string]$release.zipball_url
        $versionLabel = [string]$release.tag_name
        Write-Host "Using latest published release from ${OwnerRepo}: $versionLabel"
    } else {
        $repoMeta = Invoke-RestMethod -Uri "https://api.github.com/repos/$OwnerRepo" -Headers $headers -UseBasicParsing
        $branch = if ($repoMeta.default_branch) { [string]$repoMeta.default_branch } else { 'main' }
        $archiveUrl = "https://api.github.com/repos/$OwnerRepo/zipball/$branch"
        $versionLabel = "branch:$branch"
        $usedFallbackBranch = $true
        Write-ArchWarn "No published GitHub release found for $OwnerRepo. Falling back to default branch '$branch' (unpinned source)."
    }

    $archiveFile = Join-Path $workTmp 'source.zip'
    Invoke-WebRequest -Uri $archiveUrl -Headers $headers -OutFile $archiveFile -UseBasicParsing
    $fileHash = (Get-FileHash -LiteralPath $archiveFile -Algorithm SHA256).Hash

    $expandedDir = Join-Path $workTmp 'expanded'
    $payloadDir = Expand-ArchMcpZipPayload -ArchivePath $archiveFile -DestinationRoot $expandedDir -RequiredFiles $RequiredFiles

    $backupDir = Backup-ArchMcpPath -TargetPath $DestinationDir -ExcludeDirs @('.venv', '.venv-modern', '.git', '__pycache__', '.pytest_cache')
    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null

    # Sync source files into DestinationDir WITHOUT touching .venv (so running python.exe processes never block installation!)
    & robocopy.exe $payloadDir $DestinationDir /MIR /XD '.venv' '.venv-modern' '.git' '__pycache__' '.pytest_cache' /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "Failed to sync downloaded repository files into '$DestinationDir' (robocopy exit code $LASTEXITCODE)."
    }
    $global:LASTEXITCODE = 0

    return [pscustomobject]@{
        Repository         = $OwnerRepo
        InstalledPath      = $DestinationDir
        BackupPath         = $backupDir
        VersionLabel       = $versionLabel
        UsedFallbackBranch = $usedFallbackBranch
        ArchiveSha256      = $fileHash
        ReusedExisting     = $false
    }
}

function Invoke-ArchMcpUvSync {
    <#
    .SYNOPSIS
        Runs `uv sync --project $ProjectDir` safely.
        If `.venv\Scripts\python.exe` is locked by an active OpenCode or Claude Desktop MCP session,
        treats the existing synced `.venv` as ready instead of failing the installation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $UvExe,
        [Parameter(Mandatory = $true)] [string] $ProjectDir,
        [string[]] $ExtraArgs = @()
    )
    $venvPython = Join-Path $ProjectDir '.venv\Scripts\python.exe'
    $hadExistingVenv = Test-Path -LiteralPath $venvPython -PathType Leaf

    $syncArgs = @('sync', '--project', $ProjectDir) + @($ExtraArgs)
    $res = Invoke-ArchMcpNativeCommand -FilePath $UvExe -ArgumentList $syncArgs
    $output = $res.Output
    $exitCode = $res.ExitCode

    if ($exitCode -eq 0) {
        Write-ArchOk 'Python dependencies synchronized.'
        return
    }

    if ($hadExistingVenv -and ($output -match '(?i)Access is denied|os error 5|being used by another process|permission denied|failed to remove')) {
        Write-ArchWarn 'Existing Python .venv is currently in use by an active MCP session (e.g., OpenCode or Claude Desktop); reusing existing synced environment.'
        return
    }

    if ($ExtraArgs.Count -gt 0) {
        Write-ArchWarn 'Retrying standard uv sync without optional extras...'
        $res2 = Invoke-ArchMcpNativeCommand -FilePath $UvExe -ArgumentList @('sync', '--project', $ProjectDir)
        $output2 = $res2.Output
        $exitCode2 = $res2.ExitCode
        if ($exitCode2 -eq 0) {
            Write-ArchOk 'Python dependencies synchronized.'
            return
        }
        if ($hadExistingVenv -and ($output2 -match '(?i)Access is denied|os error 5|being used by another process|permission denied|failed to remove')) {
            Write-ArchWarn 'Existing Python .venv is currently in use by an active MCP session; reusing existing synced environment.'
            return
        }
    }

    Write-Host $output -ForegroundColor Red
    throw "uv sync failed with exit code $exitCode"
}

function Find-OpenCodeCli {
    $cmd = Get-Command 'opencode.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) { return $cmd.Source }
    $cmd2 = Get-Command 'opencode' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd2 -and (Test-Path -LiteralPath $cmd2.Source -PathType Leaf)) { return $cmd2.Source }

    $candidates = @(
        'F:\Installed Data\OpenCode\CLI V2\opencode.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\OpenCode\opencode.exe'),
        (Join-Path $env:LOCALAPPDATA 'OpenCode\opencode.exe'),
        (Join-Path $env:USERPROFILE '.opencode\bin\opencode.exe'),
        (Join-Path $env:APPDATA 'npm\opencode.cmd'),
        (Join-Path $env:ProgramFiles 'OpenCode\opencode.exe')
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'OpenCode\opencode.exe')
    }

    $appPathKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\opencode.exe',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\opencode.exe',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\opencode.exe'
    )
    foreach ($key in $appPathKeys) {
        try {
            $registered = (Get-Item -LiteralPath $key -ErrorAction Stop).GetValue('')
            if ($registered -and (Test-Path -LiteralPath $registered -PathType Leaf)) { $candidates += $registered }
        } catch { }
    }

    foreach ($candidate in ($candidates | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }

    $skip = '\\(Windows|WinSxS|ProgramData|\$Recycle\.Bin|System Volume Information|node_modules|\.git|\.cache|AppData\\Local\\Temp)\\'
    try {
        foreach ($drive in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
            try {
                $found = Get-ChildItem -LiteralPath ($drive.DeviceID + '\') -Filter 'opencode.exe' -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch $skip } | Select-Object -First 1
                if ($found) { return $found.FullName }
            } catch { }
        }
    } catch { }
    return $null
}

function Get-ClaudeDesktopConfigPaths {
    <#
    .SYNOPSIS
        Returns ALL relevant claude_desktop_config.json paths on Windows:
        1. Standard installer location: %APPDATA%\Claude\claude_desktop_config.json
        2. Microsoft Store MSIX virtualized location: %LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude_desktop_config.json
    #>
    $paths = @()
    $standardPath = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
    $paths += $standardPath

    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot -PathType Container) {
        $storeDirs = @(Get-ChildItem -LiteralPath $packagesRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)
        foreach ($sd in $storeDirs) {
            $storeCfg = Join-Path $sd.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json'
            $paths += $storeCfg
        }
    }
    return @($paths | Select-Object -Unique)
}

function Write-Utf8NoBomFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath,
        [Parameter(Mandatory = $true)] [string] $Content
    )
    $dir = Split-Path -Parent $FilePath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($FilePath, $Content, $utf8NoBom)
}

function Set-IniSectionKeyValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $IniPath,
        [Parameter(Mandatory = $true)] [string] $Section,
        [Parameter(Mandatory = $true)] [hashtable] $KeyValues,
        [string] $AppendListPathKey = $null,
        [string] $AppendListPathValue = $null
    )
    $dir = Split-Path -Parent $IniPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $backup = Backup-ArchMcpPath -TargetPath $IniPath

    $lines = @()
    if (Test-Path -LiteralPath $IniPath -PathType Leaf) {
        $lines = @(Get-Content -LiteralPath $IniPath -Encoding UTF8)
    }

    $sectionHeader = "[$Section]"
    $secStart = -1
    $secEnd = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -ieq $sectionHeader) {
            $secStart = $i
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j].Trim() -match '^\[.+\]$') {
                    $secEnd = $j
                    break
                }
            }
            break
        }
    }

    if ($AppendListPathKey -and $AppendListPathValue) {
        $existingRaw = $null
        if ($secStart -ge 0) {
            for ($k = $secStart + 1; $k -lt $secEnd; $k++) {
                if ($lines[$k] -match "^\s*$([regex]::Escape($AppendListPathKey))\s*=\s*(.*)$") {
                    $existingRaw = $Matches[1].Trim()
                    break
                }
            }
        }
        $paths = @()
        if ($existingRaw -and $existingRaw -match '^\[(.*)\]$') {
            $inner = $Matches[1]
            foreach ($m in [regex]::Matches($inner, '"([^"]+)"')) {
                $paths += $m.Groups[1].Value
            }
        }
        $normalizedNew = $AppendListPathValue
        $alreadyPresent = $false
        foreach ($p in $paths) {
            if ($p.TrimEnd('\', '/') -ieq $normalizedNew.TrimEnd('\', '/')) {
                $alreadyPresent = $true
                break
            }
        }
        if (-not $alreadyPresent) {
            $paths += $normalizedNew
        }
        $quotedPlain = @($paths | ForEach-Object { '"' + $_ + '"' })
        $KeyValues[$AppendListPathKey] = '[' + ($quotedPlain -join ', ') + ']'
    }

    if ($secStart -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') {
            $lines += ''
        }
        $lines += $sectionHeader
        foreach ($kv in $KeyValues.GetEnumerator()) {
            $lines += "$($kv.Key) = $($kv.Value)"
        }
    } else {
        $remainingKeys = @{}
        foreach ($kv in $KeyValues.GetEnumerator()) { $remainingKeys[$kv.Key] = $kv.Value }

        for ($k = $secStart + 1; $k -lt $secEnd; $k++) {
            foreach ($keyName in @($remainingKeys.Keys)) {
                if ($lines[$k] -match "^\s*$([regex]::Escape($keyName))\s*=") {
                    $lines[$k] = "$keyName = $($remainingKeys[$keyName])"
                    $remainingKeys.Remove($keyName)
                    break
                }
            }
        }
        if ($remainingKeys.Count -gt 0) {
            $insertLines = @()
            foreach ($kv in $remainingKeys.GetEnumerator()) {
                $insertLines += "$($kv.Key) = $($kv.Value)"
            }
            $before = if ($secEnd -gt 0) { $lines[0..($secEnd - 1)] } else { @() }
            $after = if ($secEnd -lt $lines.Count) { $lines[$secEnd..($lines.Count - 1)] } else { @() }
            $lines = @($before) + @($insertLines) + @($after)
        }
    }

    Write-Utf8NoBomFile -FilePath $IniPath -Content ($lines -join "`r`n")
    return $backup
}

function Update-StandardMcpServersJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $ConfigFile,
        [Parameter(Mandatory = $true)] [string] $ServerName,
        [Parameter(Mandatory = $true)] [string] $Command,
        [string[]] $Arguments = @(),
        [hashtable] $EnvironmentVariables = @{}
    )
    $backupFile = Backup-ArchMcpPath -TargetPath $ConfigFile
    $cfgDir = Split-Path -Parent $ConfigFile
    if ($cfgDir -and -not (Test-Path -LiteralPath $cfgDir)) {
        New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    }

    $rootObj = [ordered]@{}
    if (Test-Path -LiteralPath $ConfigFile -PathType Leaf) {
        try {
            $rawBytes = [System.IO.File]::ReadAllBytes($ConfigFile)
            # Strip UTF-8 BOM if present when reading
            $offset = 0
            if ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) {
                $offset = 3
            }
            $rawJson = [System.Text.Encoding]::UTF8.GetString($rawBytes, $offset, $rawBytes.Length - $offset)
            if ($rawJson -and $rawJson.Trim()) {
                $parsed = ConvertFrom-Json -InputObject $rawJson
                if ($parsed) {
                    foreach ($prop in $parsed.PSObject.Properties) {
                        $rootObj[$prop.Name] = $prop.Value
                    }
                }
            }
        } catch {
            throw "Existing config file '$ConfigFile' is not valid JSON. Aborting to preserve user config. Backup: $backupFile"
        }
    }

    $mcpServers = [ordered]@{}
    if ($rootObj.Contains('mcpServers') -and $null -ne $rootObj['mcpServers']) {
        foreach ($p in $rootObj['mcpServers'].PSObject.Properties) {
            $mcpServers[$p.Name] = $p.Value
        }
    }
    $serverEntry = [ordered]@{
        command = $Command
        args    = @($Arguments)
    }
    if ($EnvironmentVariables.Count -gt 0) {
        $serverEntry['env'] = $EnvironmentVariables
    }
    $mcpServers[$ServerName] = [pscustomobject]$serverEntry
    $rootObj['mcpServers'] = [pscustomobject]$mcpServers

    $jsonOut = ConvertTo-Json -InputObject ([pscustomobject]$rootObj) -Depth 10
    # Write strictly as UTF-8 WITHOUT BOM (Node.js / Electron JSON.parse in Claude Desktop rejects UTF-8 BOM!)
    Write-Utf8NoBomFile -FilePath $ConfigFile -Content $jsonOut
    return $backupFile
}

function Get-ClaudeDesktopConfigTargets {
    <#
    .SYNOPSIS
        Returns the claude_desktop_config.json files that must be updated, in priority order.
        Claude Desktop 3.x (MSIX) keeps its config in %LOCALAPPDATA%\Claude-Data\claude_<family>\ (confirmed via
        Settings > Developer > Edit Config on a real install). Older builds used the package-private
        LocalCache\Roaming\Claude folder (which shadows %APPDATA%\Claude) or plain %APPDATA%\Claude.
        When a Claude-Data folder exists it is the effective config and the only target; otherwise the older locations are used.
    #>
    $standard = [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Claude/claude_desktop_config.json'))
    $legacy = @()
    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot -PathType Container) {
        foreach ($sd in @(Get-ChildItem -LiteralPath $packagesRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)) {
            $legacy += [System.IO.Path]::GetFullPath((Join-Path $sd.FullName 'LocalCache/Roaming/Claude/claude_desktop_config.json'))
        }
    }
    $seed = $null
    foreach ($c in (@($legacy) + @($standard))) { if (Test-Path -LiteralPath $c -PathType Leaf) { $seed = $c; break } }

    $targets = @()
    $dataRoot = Join-Path $env:LOCALAPPDATA 'Claude-Data'
    if (Test-Path -LiteralPath $dataRoot -PathType Container) {
        foreach ($dd in @(Get-ChildItem -LiteralPath $dataRoot -Directory -Filter 'claude_*' -ErrorAction SilentlyContinue)) {
            $targets += [pscustomobject]@{ Path = [System.IO.Path]::GetFullPath((Join-Path $dd.FullName 'claude_desktop_config.json')); Kind = 'Claude-Data'; SeedFrom = $seed }
        }
    }
    if ($targets.Count -gt 0) { return @($targets) }

    foreach ($l in $legacy) { $targets += [pscustomobject]@{ Path = $l; Kind = 'Store'; SeedFrom = $standard } }
    $stdDirExists = Test-Path -LiteralPath (Split-Path -Parent $standard) -PathType Container
    if ($targets.Count -eq 0 -or $stdDirExists) {
        $targets += [pscustomobject]@{ Path = $standard; Kind = 'Standard'; SeedFrom = $null }
    }
    return @($targets)
}

function Get-ArchMcpClaudeLaunchSpec {
    <#
    .SYNOPSIS
        Claude Desktop launches servers with a minimal environment, no console, and a startup timeout.
        `uv run` adds a dependency re-check/network/cache step and writes into the repo folder at launch
        (redirected under MSIX), so for Claude Desktop launch the already-synced .venv directly.
        Falls back to the original command when the venv layout is not the expected one.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $Command,
        [string[]] $Arguments = @(),
        [hashtable] $EnvironmentVariables = @{}
    )
    $envOut = @{}
    foreach ($k in $EnvironmentVariables.Keys) { $envOut[$k] = [string]$EnvironmentVariables[$k] }
    $envOut['PYTHONUNBUFFERED'] = '1'
    $envOut['PYTHONUTF8'] = '1'
    $spec = [pscustomobject]@{ Command = $Command; Arguments = @($Arguments); Env = $envOut; Direct = $false }

    $args2 = @($Arguments)
    if ((Split-Path -Leaf $Command) -notmatch '^uv(\.exe)?$' -or $args2.Count -lt 4 -or $args2[0] -ne 'run' -or $args2[1] -ne '--directory') { return $spec }
    $dir = $args2[2]
    $target = $args2[3]
    $scripts = [System.IO.Path]::GetFullPath((Join-Path $dir '.venv/Scripts'))
    $py = Join-Path $scripts 'python.exe'
    if (-not (Test-Path -LiteralPath $py -PathType Leaf)) { return $spec }
    if ($target -match '\.py$') {
        $script = if ([System.IO.Path]::IsPathRooted($target)) { $target } else { Join-Path $dir $target }
        if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { return $spec }
        $spec.Command = $py; $spec.Arguments = @([System.IO.Path]::GetFullPath($script)) + @($args2[4..($args2.Count)] | Where-Object { $_ }); $spec.Direct = $true
    } else {
        $exe = Join-Path $scripts ($target + '.exe')
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $spec }
        $spec.Command = $exe; $spec.Arguments = @($args2[4..($args2.Count)] | Where-Object { $_ }); $spec.Direct = $true
    }
    return $spec
}

function Get-ArchMcpVenvPython {
    param([Parameter(Mandatory = $true)] [string] $EnvDir)
    foreach ($rel in @('Scripts/python.exe', 'bin/python')) {
        $c = Join-Path $EnvDir $rel
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    return $null
}

function Initialize-ArchMcpPipEnv {
    <#
    .SYNOPSIS
        Builds a pinned-Python venv from a project's pyproject.toml with `uv pip install --override` instead of `uv sync`.
        Needed when upstream constraints are unsatisfiable (e.g. Rhino 7 MCP pins anyio<4 while every mcp 1.x needs anyio>=4.5,
        and its uv.lock is stale), or when uv would pick an interpreter too new for the locked wheels (Python 3.14).
        A venv built with another Python version is recreated. Returns the venv python path.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $UvExe,
        [Parameter(Mandatory = $true)] [string] $ProjectDir,
        [string] $EnvName = '.venv',
        [string] $PythonVersion = '3.12',
        [string[]] $OverrideLines = @()
    )
    $envDir = Join-Path $ProjectDir $EnvName
    $py = Get-ArchMcpVenvPython -EnvDir $envDir
    if ($py) {
        $ver = ''
        try { $ver = ((& $py -c "import sys;print('%d.%d' % sys.version_info[:2])") | Out-String).Trim() } catch { }
        if ($ver -ne $PythonVersion) {
            Write-ArchWarn "Existing $EnvName uses Python '$ver' (need $PythonVersion); recreating it."
            try { Remove-Item -LiteralPath $envDir -Recurse -Force -ErrorAction Stop } catch { throw "Cannot recreate $envDir (in use?). Close the AI client / app that uses it and retry. $($_.Exception.Message)" }
            $py = $null
        }
    }
    if (-not $py) {
        $rv = Invoke-ArchMcpNativeCommand -FilePath $UvExe -ArgumentList @('venv', '--python', $PythonVersion, $envDir)
        if ($rv.ExitCode -ne 0) { throw "uv could not create a Python $PythonVersion environment: $($rv.Output)" }
        $py = Get-ArchMcpVenvPython -EnvDir $envDir
        if (-not $py) { throw "Python environment was not created at $envDir" }
    }
    $ov = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($ov, ((@($OverrideLines) -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
        $ri = Invoke-ArchMcpNativeCommand -FilePath $UvExe -ArgumentList @('pip', 'install', '--python', $py, '-r', (Join-Path $ProjectDir 'pyproject.toml'), '--override', $ov)
        if ($ri.ExitCode -ne 0) { throw "Dependency install failed: $($ri.Output)" }
    } finally { Remove-Item -LiteralPath $ov -Force -ErrorAction SilentlyContinue }
    Write-ArchOk "Python $PythonVersion environment ready ($EnvName)."
    return $py
}

function Initialize-ArchMcpModernEnv {
    <#
    .SYNOPSIS
        Creates a SEPARATE venv (.venv-modern) with the MCP Python SDK 2.x for clients that speak MCP 2026-07-28 (Antigravity).
        The normal .venv (used by Claude Desktop / OpenCode via `uv run`) is never modified. Returns the venv python path.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $UvExe,
        [Parameter(Mandatory = $true)] [string] $ProjectDir
    )
    $envDir = Join-Path $ProjectDir '.venv-modern'
    $py = Join-Path $envDir 'Scripts\python.exe'
    $old = $env:UV_PROJECT_ENVIRONMENT
    try {
        $env:UV_PROJECT_ENVIRONMENT = $envDir
        $r1 = Invoke-ArchMcpNativeCommand -FilePath $UvExe -ArgumentList @('sync', '--project', $ProjectDir)
        if ($r1.ExitCode -ne 0) { throw "uv sync for the MCP 2.x environment failed: $($r1.Output)" }
    } finally {
        if ($null -eq $old) { Remove-Item Env:UV_PROJECT_ENVIRONMENT -ErrorAction SilentlyContinue } else { $env:UV_PROJECT_ENVIRONMENT = $old }
    }
    $r2 = Invoke-ArchMcpNativeCommand -FilePath $UvExe -ArgumentList @('pip', 'install', '--python', $py, 'mcp>=2,<3')
    if ($r2.ExitCode -ne 0) { throw "Installing MCP Python SDK 2.x failed: $($r2.Output)" }
    if (-not (Test-Path -LiteralPath $py -PathType Leaf)) { throw "MCP 2.x environment python not found: $py" }
    return $py
}

function Test-ArchMcpStdioHandshake {
    <#
    .SYNOPSIS
        Starts the server exactly as an MCP client would (stdio) and performs initialize + tools/list.
        Proves layers 3-4 only (server starts, tools discovered); it does NOT prove the AI client shows them.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $Command,
        [string[]] $Arguments = @(),
        [hashtable] $EnvironmentVariables = @{},
        [int] $TimeoutSec = 90,
        [switch] $Modern
    )
    $res = [pscustomobject]@{ Started = $false; Initialized = $false; ServerName = $null; ToolCount = 0; ToolNames = @(); StdoutNoise = @(); StderrTail = ''; Error = $null; Seconds = 0 }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = $null
    try {
        $q = { param($s) '"' + ($s -replace '"', '\"') + '"' }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Command
        $psi.Arguments = (@($Arguments | ForEach-Object { & $q $_ }) -join ' ')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
        foreach ($k in $EnvironmentVariables.Keys) { $psi.EnvironmentVariables[[string]$k] = [string]$EnvironmentVariables[$k] }
        $proc = [System.Diagnostics.Process]::Start($psi)
        $res.Started = $true
        $errTask = $proc.StandardError.ReadToEndAsync()
        $stdin = $proc.StandardInput
        $send = { param($o) $stdin.WriteLine(($o | ConvertTo-Json -Compress -Depth 8)); $stdin.Flush() }
        $read = {
            param($id)
            $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
            while ([DateTime]::UtcNow -lt $deadline) {
                $t = $proc.StandardOutput.ReadLineAsync()
                $left = [int]([Math]::Max(1, ($deadline - [DateTime]::UtcNow).TotalMilliseconds))
                if (-not $t.Wait($left)) { return $null }
                if ($null -eq $t.Result) { return $null }
                $line = $t.Result.Trim()
                if (-not $line) { continue }
                try { $obj = $line | ConvertFrom-Json } catch { $res.StdoutNoise += $line.Substring(0, [Math]::Min(120, $line.Length)); continue }
                if ($obj.PSObject.Properties.Name -contains 'id' -and $obj.id -eq $id) { return $obj }
            }
            return $null
        }
        if ($Modern) {
            # MCP 2026-07-28 (stateless): no initialize; the first request is server/discover and every request carries _meta.
            $meta = [ordered]@{ 'io.modelcontextprotocol/protocolVersion' = '2026-07-28'; 'io.modelcontextprotocol/clientInfo' = [ordered]@{ name = 'antigravity'; version = '1.0.0' }; 'io.modelcontextprotocol/clientCapabilities' = @{} }
            & $send ([ordered]@{ jsonrpc = '2.0'; id = 1; method = 'server/discover'; params = [ordered]@{ _meta = $meta } })
            $init = & $read 1
            if (-not $init -or -not $init.result) { throw 'No valid response to MCP 2026-07-28 server/discover (server rejected it, exited, or timed out).' }
            $res.Initialized = $true
            try { $res.ServerName = [string]$init.result.serverInfo.name } catch { }
            & $send ([ordered]@{ jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = [ordered]@{ _meta = $meta } })
        } else {
            & $send ([ordered]@{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = [ordered]@{ protocolVersion = '2024-11-05'; capabilities = @{}; clientInfo = [ordered]@{ name = 'claude-ai'; version = '0.1.0' } } })
            $init = & $read 1
            if (-not $init -or -not $init.result) { throw 'No valid response to MCP initialize (server exited, timed out, or wrote non-JSON to stdout).' }
            $res.Initialized = $true
            $res.ServerName = [string]$init.result.serverInfo.name
            & $send ([ordered]@{ jsonrpc = '2.0'; method = 'notifications/initialized' })
            & $send ([ordered]@{ jsonrpc = '2.0'; id = 2; method = 'tools/list' })
        }
        $tl = & $read 2
        if (-not $tl -or -not $tl.result) { throw 'No valid response to tools/list.' }
        $res.ToolNames = @($tl.result.tools | ForEach-Object { $_.name })
        $res.ToolCount = $res.ToolNames.Count
        if ($res.ToolCount -eq 0) { throw 'Server initialized but exposes zero tools.' }
    } catch {
        $res.Error = $_.Exception.Message
    } finally {
        if ($proc) {
            try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
            try { $res.StderrTail = ($errTask.Result); if ($res.StderrTail.Length -gt 600) { $res.StderrTail = $res.StderrTail.Substring($res.StderrTail.Length - 600) } } catch { }
        }
        $sw.Stop(); $res.Seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
    }
    return $res
}

function Read-ArchMcpJsonConfig {
    param([Parameter(Mandatory = $true)] [string] $Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $off = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $off = 3 }
    $txt = [System.Text.Encoding]::UTF8.GetString($bytes, $off, $bytes.Length - $off)
    if (-not $txt.Trim()) { return $null }
    return (ConvertFrom-Json -InputObject $txt)
}

function Register-ArchMcpWithClaudeDesktop {
    <#
    .SYNOPSIS
        Registers an MCP server for Claude Desktop, validates the written config, proves the exact registered command
        speaks MCP (initialize + tools/list), and rolls back every touched file on any failure.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $ServerName,
        [Parameter(Mandatory = $true)] [string] $Command,
        [string[]] $Arguments = @(),
        [hashtable] $EnvironmentVariables = @{},
        [string] $CustomConfigPath = $null,
        [switch] $SkipHandshake
    )
    $spec = Get-ArchMcpClaudeLaunchSpec -Command $Command -Arguments $Arguments -EnvironmentVariables $EnvironmentVariables
    if ($spec.Direct) { Write-ArchOk "Claude Desktop launch: direct venv interpreter (no 'uv run' at startup): $($spec.Command)" }
    else { Write-ArchWarn "Could not resolve a direct .venv launcher; Claude Desktop will use the original command: $($spec.Command)" }
    if (-not (Test-Path -LiteralPath $spec.Command -PathType Leaf)) { throw "Server executable does not exist: $($spec.Command)" }

    $targets = if ($CustomConfigPath) { @([pscustomobject]@{ Path = $CustomConfigPath; Kind = 'Custom'; SeedFrom = $null }) } else { Get-ClaudeDesktopConfigTargets }
    $anyExisting = $false
    foreach ($t in $targets) { if (Test-Path -LiteralPath $t.Path) { $anyExisting = $true } }
    if (-not $CustomConfigPath -and -not $anyExisting -and -not (Test-Path -LiteralPath (Split-Path -Parent (Split-Path -Parent $targets[0].Path)))) {
        Write-ArchWarn 'Claude Desktop does not appear to be installed for this Windows user (no config folder found). The config will still be written and used once it is installed.'
    }

    $done = @()
    try {
        foreach ($t in $targets) {
            $existedBefore = Test-Path -LiteralPath $t.Path -PathType Leaf
            # MSIX: a new file in the package-private folder would hide the user's existing %APPDATA% config, so seed it first.
            if (-not $existedBefore -and $t.SeedFrom -and (Test-Path -LiteralPath $t.SeedFrom -PathType Leaf)) {
                Write-Utf8NoBomFile -FilePath $t.Path -Content ([System.IO.File]::ReadAllText($t.SeedFrom))
                Write-ArchWarn "Seeded new config from existing $($t.SeedFrom) so current settings and servers are preserved."
            }
            if (Test-Path -LiteralPath $t.Path -PathType Leaf) {
                $cur = Read-ArchMcpJsonConfig -Path $t.Path
                if ($cur -and $cur.mcpServers -and ($cur.mcpServers.PSObject.Properties.Name -contains $ServerName)) {
                    $old = $cur.mcpServers.$ServerName
                    if ($old.command -ne $spec.Command -or (@($old.args) -join '|') -ne ($spec.Arguments -join '|')) {
                        Write-ArchWarn "Replacing existing '$ServerName' entry in $($t.Path) (previous command: $($old.command)). The backup keeps the old value."
                    }
                }
            }
            $bkp = Update-StandardMcpServersJsonFile -ConfigFile $t.Path -ServerName $ServerName -Command $spec.Command -Arguments $spec.Arguments -EnvironmentVariables $spec.Env
            $done += [pscustomobject]@{ Path = $t.Path; Backup = $bkp; Existed = $existedBefore; Kind = $t.Kind }
            $chk = Read-ArchMcpJsonConfig -Path $t.Path
            $e = $null
            if ($chk -and $chk.mcpServers) { $e = $chk.mcpServers.$ServerName }
            if (-not $e -or $e.command -ne $spec.Command -or @($e.args).Count -ne $spec.Arguments.Count) { throw "Post-write validation failed for $($t.Path): '$ServerName' entry missing or altered." }
            Write-ArchOk "Claude Desktop config updated and re-validated ($($t.Kind)): $($t.Path)"
        }
        if (-not $SkipHandshake) {
            Write-ArchStep "Verifying '$ServerName' speaks MCP using the exact registered command (initialize + tools/list)"
            $hs = Test-ArchMcpStdioHandshake -Command $spec.Command -Arguments $spec.Arguments -EnvironmentVariables $spec.Env -TimeoutSec 90
            if ($hs.StdoutNoise.Count -gt 0) { Write-ArchWarn "Server wrote non-JSON text to stdout (breaks MCP clients): $($hs.StdoutNoise[0])" }
            if ($hs.Error) { throw "MCP handshake failed after $($hs.Seconds)s: $($hs.Error) | stderr: $($hs.StderrTail)" }
            Write-ArchOk "MCP handshake OK in $($hs.Seconds)s: server '$($hs.ServerName)' exposes $($hs.ToolCount) tools. (Layers 1-4 verified; Claude Desktop exposure still needs a full restart.)"
            if ($hs.Seconds -gt 45) { Write-ArchWarn 'Server needed more than 45s to initialize; Claude Desktop may time out on a cold start. Re-run once to warm caches.' }
        }
    } catch {
        foreach ($d in $done) {
            try {
                if ($d.Backup -and (Test-Path -LiteralPath $d.Backup)) { Copy-Item -LiteralPath $d.Backup -Destination $d.Path -Force }
                elseif (-not $d.Existed -and (Test-Path -LiteralPath $d.Path)) { Remove-Item -LiteralPath $d.Path -Force }
            } catch { Write-ArchWarn "Rollback of $($d.Path) failed: $($_.Exception.Message)" }
        }
        throw "Claude Desktop registration rolled back. $($_.Exception.Message)"
    }

    $running = $false
    try { $running = [bool](Get-Process -Name 'claude' -ErrorAction SilentlyContinue) } catch { }
    if ($running) { Write-ArchWarn 'Claude Desktop is RUNNING and has NOT loaded this server yet. Quit it completely (right-click its tray icon > Quit), then reopen it. Tools appear only after that.' }
    else { Write-ArchWarn 'Open Claude Desktop now; the tools appear after launch. If it was already open, quit it completely from the tray first.' }
    if ($SkipHandshake) { Write-ArchWarn "Status: config registered+valid only (server start / tool discovery were NOT tested). NOT confirmed: Claude Desktop showing the tools, live '$ServerName' host operation." }
    else { Write-ArchWarn "Status: config registered+valid, server starts, tools discovered. NOT yet confirmed: Claude Desktop showing the tools, and a live '$ServerName' host operation." }
    $first = $done[0]
    return [pscustomobject]@{ Agent = 'Claude Desktop'; ConfigPath = $first.Path; ConfigPaths = @($done | ForEach-Object { $_.Path }); BackupPath = $first.Backup; UsedCli = $false; Launch = $spec }
}

function Get-ArchMcpAgentConfigTargets {
    <#
    .SYNOPSIS
        Resolves MCP config file(s) for an agent without hard-coding one location.
        Order: explicit env overrides first, then known per-agent candidates. Existing files win (all existing candidates
        are returned, first = primary); if none exists, the first candidate whose parent folder exists, else the preferred default.
        Candidates are conventions + overrides, not guarantees: the chosen path is always printed by the installer.
    #>
    param([Parameter(Mandatory = $true)] [string] $Agent)
    $h = $env:USERPROFILE
    if (-not $h) { $h = $HOME }
    $a = $Agent.Trim().ToLowerInvariant()
    $c = @()
    if ($a -match 'antigravity') {
        $c += (Join-Path $h '.gemini/config/mcp_config.json')
        $c += (Join-Path $h '.gemini/antigravity/mcp_config.json')
    } elseif ($a -match 'codex') {
        $base = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $h '.codex' }
        $c += (Join-Path $base 'config.toml')
    } elseif ($a -match 'claude code') {
        $base = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { $h }
        $c += (Join-Path $base '.claude.json')
    } elseif ($a -match 'opencode') {
        if ($env:OPENCODE_CONFIG) { $c += $env:OPENCODE_CONFIG }
        $c += (Join-Path $h '.config/opencode/opencode.json')
        if ($env:XDG_CONFIG_HOME) { $c += (Join-Path $env:XDG_CONFIG_HOME 'opencode/opencode.json') }
    }
    $c = @($c | ForEach-Object { [System.IO.Path]::GetFullPath($_) } | Select-Object -Unique)
    if ($c.Count -eq 0) { return @() }
    $existing = @($c | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($existing.Count -gt 0) { return $existing }
    foreach ($x in $c) { if (Test-Path -LiteralPath (Split-Path -Parent $x) -PathType Container) { return @($x) } }
    return @($c[0])
}

function Register-ArchMcpWithAgent {
    <#
    .SYNOPSIS
        Registers an MCP server entry with the selected AI Agent while preserving all existing user settings and MCP servers.
        Writes UTF-8 WITHOUT BOM and updates both standalone and Microsoft Store paths for Claude Desktop.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $AgentName,
        [Parameter(Mandatory = $true)] [string] $ServerName,
        [Parameter(Mandatory = $true)] [string] $Command,
        [string[]] $Arguments = @(),
        [hashtable] $EnvironmentVariables = @{},
        [string] $CustomConfigPath = $null
    )

    $normalizedAgent = $AgentName.Trim().ToLowerInvariant()
    $cliRegistered = $false
    $configFile = $CustomConfigPath
    $backupFile = $null

    if ($normalizedAgent -match 'opencode') {
        $ocTargets = if ($CustomConfigPath) { @($CustomConfigPath) } else { @(Get-ArchMcpAgentConfigTargets -Agent 'opencode') }
        $configFile = $ocTargets[0]
        $backupFile = Backup-ArchMcpPath -TargetPath $configFile
        $opencodeExe = Find-OpenCodeCli
        if ($opencodeExe -and -not $CustomConfigPath) {
            try {
                # Remove any stale CLI registration first so re-adding with updated command always succeeds
                Invoke-ArchMcpNativeCommand -FilePath $opencodeExe -ArgumentList @('mcp', 'remove', $ServerName, '--global') | Out-Null
            } catch { }
            try {
                $cliArgs = @('mcp', 'add', $ServerName, '--global')
                foreach ($ev in $EnvironmentVariables.GetEnumerator()) {
                    $cliArgs += '--env'
                    $cliArgs += "$($ev.Key)=$($ev.Value)"
                }
                $cliArgs += '--'
                $cliArgs += $Command
                $cliArgs += $Arguments
                $ocRes = Invoke-ArchMcpNativeCommand -FilePath $opencodeExe -ArgumentList $cliArgs
                if ($ocRes.ExitCode -eq 0) {
                    $cliRegistered = $true
                    Write-ArchOk "Registered '$ServerName' via OpenCode CLI: $opencodeExe"
                }
            } catch {
                Write-ArchWarn "OpenCode CLI invocation reported an issue; ensuring JSON configuration is updated directly."
            }
        }

        foreach ($ocFile in $ocTargets) {
            $cfgDir = Split-Path -Parent $ocFile
            if ($cfgDir -and -not (Test-Path -LiteralPath $cfgDir)) {
                New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
            }
            $rootObj = @{}
            if (Test-Path -LiteralPath $ocFile -PathType Leaf) {
                try {
                    $rawJson = Get-Content -LiteralPath $ocFile -Raw -Encoding UTF8
                    $cleanJson = [regex]::Replace($rawJson, '(?m)^\s*//.*$', '')
                    $parsed = ConvertFrom-Json -InputObject $cleanJson
                    if ($parsed) {
                        foreach ($prop in $parsed.PSObject.Properties) {
                            $rootObj[$prop.Name] = $prop.Value
                        }
                    }
                } catch {
                    throw "Existing OpenCode config at '$ocFile' could not be parsed safely. Aborting to avoid losing user config. Backup at: $backupFile"
                }
            }
            if (-not $rootObj.ContainsKey('$schema')) {
                $rootObj['$schema'] = 'https://opencode.ai/config.json'
            }
            $cmdArray = @($Command) + @($Arguments)
            $mcpObj = @{}
            if ($rootObj.ContainsKey('mcp') -and $null -ne $rootObj['mcp']) {
                foreach ($p in $rootObj['mcp'].PSObject.Properties) {
                    $mcpObj[$p.Name] = $p.Value
                }
            }

            if ($mcpObj.ContainsKey('servers') -and $null -ne $mcpObj['servers']) {
                $serversMap = @{}
                foreach ($sp in $mcpObj['servers'].PSObject.Properties) {
                    $serversMap[$sp.Name] = $sp.Value
                }
                $entry = [ordered]@{
                    type    = 'local'
                    command = $cmdArray
                }
                if ($EnvironmentVariables.Count -gt 0) { $entry['environment'] = $EnvironmentVariables }
                $serversMap[$ServerName] = [pscustomobject]$entry
                $mcpObj['servers'] = [pscustomobject]$serversMap
            } else {
                $entry = [ordered]@{
                    type    = 'local'
                    command = $cmdArray
                    enabled = $true
                }
                if ($EnvironmentVariables.Count -gt 0) { $entry['environment'] = $EnvironmentVariables }
                $mcpObj[$ServerName] = [pscustomobject]$entry
            }
            $rootObj['mcp'] = [pscustomobject]$mcpObj
            $jsonOut = ConvertTo-Json -InputObject ([pscustomobject]$rootObj) -Depth 10
            Write-Utf8NoBomFile -FilePath $ocFile -Content $jsonOut
        }
        return [pscustomobject]@{
            Agent      = 'OpenCode'
            ConfigPath = $configFile
            BackupPath = $backupFile
            UsedCli    = $cliRegistered
        }
    }
    elseif ($normalizedAgent -match 'codex') {
        if (-not $configFile) {
            $configFile = @(Get-ArchMcpAgentConfigTargets -Agent 'codex')[0]
        }
        $backupFile = Backup-ArchMcpPath -TargetPath $configFile
        $cfgDir = Split-Path -Parent $configFile
        if ($cfgDir -and -not (Test-Path -LiteralPath $cfgDir)) {
            New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
        }

        $codexCli = Get-Command 'codex' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($codexCli -and -not $CustomConfigPath) {
            try {
                Invoke-ArchMcpNativeCommand -FilePath $codexCli.Source -ArgumentList @('mcp', 'remove', $ServerName) | Out-Null
            } catch { }
            try {
                $cliArgs = @('mcp', 'add', $ServerName)
                foreach ($ev in $EnvironmentVariables.GetEnumerator()) {
                    $cliArgs += '--env'
                    $cliArgs += "$($ev.Key)=$($ev.Value)"
                }
                $cliArgs += '--'
                $cliArgs += $Command
                $cliArgs += $Arguments
                $cxRes = Invoke-ArchMcpNativeCommand -FilePath $codexCli.Source -ArgumentList $cliArgs
                if ($cxRes.ExitCode -eq 0) { $cliRegistered = $true }
            } catch { }
        }

        $lines = @()
        if (Test-Path -LiteralPath $configFile -PathType Leaf) {
            $lines = @(Get-Content -LiteralPath $configFile -Encoding UTF8)
        }
        $sectionHeader = "[mcp_servers.$ServerName]"
        $filtered = New-Object System.Collections.Generic.List[string]
        $skipBlock = $false
        foreach ($line in $lines) {
            $trim = $line.Trim()
            if ($trim -ieq $sectionHeader -or $trim -ieq "[mcp_servers.$ServerName.env]") {
                $skipBlock = $true
                continue
            }
            if ($skipBlock -and $trim -match '^\[.+\]$') {
                $skipBlock = $false
            }
            if (-not $skipBlock) {
                $filtered.Add($line)
            }
        }
        if ($filtered.Count -gt 0 -and $filtered[$filtered.Count - 1].Trim() -ne '') {
            $filtered.Add('')
        }
        $escapedCmd = $Command.Replace('\', '\\').Replace('"', '\"')
        $escapedArgs = @($Arguments | ForEach-Object { '"' + $_.Replace('\', '\\').Replace('"', '\"') + '"' }) -join ', '
        $filtered.Add($sectionHeader)
        $filtered.Add("command = `"$escapedCmd`"")
        $filtered.Add("args = [$escapedArgs]")
        if ($EnvironmentVariables.Count -gt 0) {
            $filtered.Add("[mcp_servers.$ServerName.env]")
            foreach ($ev in $EnvironmentVariables.GetEnumerator()) {
                $valEsc = ([string]$ev.Value).Replace('\', '\\').Replace('"', '\"')
                $filtered.Add("$($ev.Key) = `"$valEsc`"")
            }
        }
        Write-Utf8NoBomFile -FilePath $configFile -Content ($filtered -join "`r`n")
        return [pscustomobject]@{
            Agent      = 'OpenAI Codex'
            ConfigPath = $configFile
            BackupPath = $backupFile
            UsedCli    = $cliRegistered
        }
    }
    elseif ($normalizedAgent -match 'claude desktop') {
        return Register-ArchMcpWithClaudeDesktop -ServerName $ServerName -Command $Command -Arguments $Arguments `
            -EnvironmentVariables $EnvironmentVariables -CustomConfigPath $CustomConfigPath
    }
    else {
        if (-not $configFile) {
            if ($normalizedAgent -match 'claude code') {
                $configFile = @(Get-ArchMcpAgentConfigTargets -Agent 'claude code')[0]
            } elseif ($normalizedAgent -match 'antigravity') {
                $configFile = @(Get-ArchMcpAgentConfigTargets -Agent 'antigravity')[0]
            } else {
                $configFile = Join-Path (Get-ArchMcpRootDataDir) 'mcp_config.json'
            }
        }

        if ($normalizedAgent -match 'claude code' -and -not $CustomConfigPath) {
            $claudeCli = Get-Command 'claude' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($claudeCli) {
                try {
                    Invoke-ArchMcpNativeCommand -FilePath $claudeCli.Source -ArgumentList @('mcp', 'remove', '--scope', 'user', $ServerName) | Out-Null
                } catch { }
                try {
                    $cliArgs = @('mcp', 'add', '--scope', 'user', $ServerName, '--', $Command) + @($Arguments)
                    $clRes = Invoke-ArchMcpNativeCommand -FilePath $claudeCli.Source -ArgumentList $cliArgs
                    if ($clRes.ExitCode -eq 0) { $cliRegistered = $true }
                } catch { }
            }
        }

        if ($normalizedAgent -match 'antigravity') {
            # Antigravity: launch the synced venv directly (not `uv run`) and prove BOTH protocol eras before touching any config:
            # legacy initialize, and MCP 2026-07-28 server/discover (what current Antigravity sends).
            $spec = Get-ArchMcpClaudeLaunchSpec -Command $Command -Arguments $Arguments -EnvironmentVariables $EnvironmentVariables
            $isUv = ((Split-Path -Leaf $Command) -match '^uv(\.exe)?$')
            if ($spec.Direct -or -not $isUv) {
                Write-ArchOk "Antigravity launch: $($spec.Command)"
                Write-ArchStep "Verifying '$ServerName' speaks MCP (legacy initialize + 2026-07-28 server/discover) using the exact command to be registered"
                $hs = Test-ArchMcpStdioHandshake -Command $spec.Command -Arguments $spec.Arguments -EnvironmentVariables $spec.Env -TimeoutSec 90
                if ($hs.Error) { throw "MCP handshake failed after $($hs.Seconds)s: $($hs.Error) | stderr: $($hs.StderrTail)" }
                Write-ArchOk "Legacy handshake OK in $($hs.Seconds)s: '$($hs.ServerName)' exposes $($hs.ToolCount) tools."
                $hm = Test-ArchMcpStdioHandshake -Command $spec.Command -Arguments $spec.Arguments -EnvironmentVariables $spec.Env -TimeoutSec 30 -Modern
                if ($hm.Error) {
                    Write-ArchWarn "This server does NOT speak MCP 2026-07-28 (server/discover): $($hm.Error)"
                    Write-ArchWarn 'Current Antigravity versions will show it red/stuck until the upstream server moves to the MCP SDK 2.x. Claude Desktop and OpenCode are not affected. The entry is still registered.'
                } else {
                    Write-ArchOk "MCP 2026-07-28 handshake OK in $($hm.Seconds)s: $($hm.ToolCount) tools discovered."
                }
                $Command = $spec.Command; $Arguments = $spec.Arguments; $EnvironmentVariables = $spec.Env
            } else {
                Write-ArchWarn 'Could not resolve a direct .venv launcher; Antigravity will use the original command.'
            }
        }
        $backupFile = Update-StandardMcpServersJsonFile -ConfigFile $configFile -ServerName $ServerName `
            -Command $Command -Arguments $Arguments -EnvironmentVariables $EnvironmentVariables
        Write-ArchOk "Updated $AgentName config: $configFile"
        if ($normalizedAgent -match 'antigravity' -and -not $CustomConfigPath) {
            foreach ($extra in @(Get-ArchMcpAgentConfigTargets -Agent 'antigravity')) {
                if ($extra -ne $configFile -and (Test-Path -LiteralPath $extra -PathType Leaf)) {
                    $null = Update-StandardMcpServersJsonFile -ConfigFile $extra -ServerName $ServerName -Command $Command -Arguments $Arguments -EnvironmentVariables $EnvironmentVariables
                    Write-ArchOk "Also updated existing $AgentName config: $extra"
                }
            }
        }

        return [pscustomobject]@{
            Agent      = $AgentName
            ConfigPath = $configFile
            BackupPath = $backupFile
            UsedCli    = $cliRegistered
        }
    }
}

function Remove-StandardMcpServersJsonEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $ConfigFile,
        [Parameter(Mandatory = $true)] [string] $ServerName
    )
    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        return $false
    }
    $parsed = $null
    try {
        $parsed = Read-ArchMcpJsonConfig -Path $ConfigFile
    } catch {
        Write-ArchWarn "Skipping malformed JSON config at '$ConfigFile'."
        return $false
    }
    if (-not $parsed -or -not $parsed.mcpServers) {
        return $false
    }
    $propNames = @($parsed.mcpServers.PSObject.Properties.Name)
    $matchedName = $propNames | Where-Object { $_ -ieq $ServerName } | Select-Object -First 1
    if (-not $matchedName) {
        return $false
    }

    $null = Backup-ArchMcpPath -TargetPath $ConfigFile
    $rootObj = [ordered]@{}
    foreach ($prop in $parsed.PSObject.Properties) {
        $rootObj[$prop.Name] = $prop.Value
    }
    $mcpServers = [ordered]@{}
    foreach ($p in $parsed.mcpServers.PSObject.Properties) {
        if ($p.Name -ine $ServerName) {
            $mcpServers[$p.Name] = $p.Value
        }
    }
    $rootObj['mcpServers'] = [pscustomobject]$mcpServers
    $jsonOut = ConvertTo-Json -InputObject ([pscustomobject]$rootObj) -Depth 10
    Write-Utf8NoBomFile -FilePath $ConfigFile -Content $jsonOut
    return $true
}

function Remove-OpenCodeMcpServerEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $ConfigFile,
        [Parameter(Mandatory = $true)] [string] $ServerName
    )
    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        return $false
    }
    $parsed = $null
    try {
        $rawJson = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8
        $cleanJson = [regex]::Replace($rawJson, '(?m)^\s*//.*$', '')
        if ($cleanJson -and $cleanJson.Trim()) {
            $parsed = ConvertFrom-Json -InputObject $cleanJson
        }
    } catch {
        Write-ArchWarn "Skipping malformed OpenCode JSON config at '$ConfigFile'."
        return $false
    }
    if (-not $parsed -or -not $parsed.mcp) {
        return $false
    }

    $removed = $false
    $rootObj = [ordered]@{}
    foreach ($prop in $parsed.PSObject.Properties) {
        $rootObj[$prop.Name] = $prop.Value
    }
    $mcpObj = [ordered]@{}
    foreach ($p in $parsed.mcp.PSObject.Properties) {
        if ($p.Name -ieq $ServerName) {
            $removed = $true
        } elseif ($p.Name -ieq 'servers' -and $null -ne $p.Value) {
            $serversMap = [ordered]@{}
            foreach ($sp in $p.Value.PSObject.Properties) {
                if ($sp.Name -ieq $ServerName) {
                    $removed = $true
                } else {
                    $serversMap[$sp.Name] = $sp.Value
                }
            }
            $mcpObj['servers'] = [pscustomobject]$serversMap
        } else {
            $mcpObj[$p.Name] = $p.Value
        }
    }

    if (-not $removed) {
        return $false
    }
    $null = Backup-ArchMcpPath -TargetPath $ConfigFile
    $rootObj['mcp'] = [pscustomobject]$mcpObj
    $jsonOut = ConvertTo-Json -InputObject ([pscustomobject]$rootObj) -Depth 10
    Write-Utf8NoBomFile -FilePath $ConfigFile -Content $jsonOut
    return $true
}

function Remove-CodexMcpServerEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $ConfigFile,
        [Parameter(Mandatory = $true)] [string] $ServerName
    )
    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        return $false
    }
    $lines = @(Get-Content -LiteralPath $ConfigFile -Encoding UTF8)
    $sectionHeader = "[mcp_servers.$ServerName]"
    $envHeader = "[mcp_servers.$ServerName.env]"
    $filtered = New-Object System.Collections.Generic.List[string]
    $skipBlock = $false
    $removed = $false
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if ($trim -ieq $sectionHeader -or $trim -ieq $envHeader) {
            $skipBlock = $true
            $removed = $true
            continue
        }
        if ($skipBlock -and $trim -match '^\[.+\]$') {
            $skipBlock = $false
        }
        if (-not $skipBlock) {
            $filtered.Add($line)
        }
    }
    if (-not $removed) {
        return $false
    }
    $null = Backup-ArchMcpPath -TargetPath $ConfigFile
    Write-Utf8NoBomFile -FilePath $ConfigFile -Content ($filtered -join "`r`n")
    return $true
}

function Unregister-ArchMcpFromAgent {
    <#
    .SYNOPSIS
        Disables and removes an MCP server entry from the selected AI Agent (and optionally all existing agent configs on disk).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $AgentName,
        [Parameter(Mandatory = $true)] [string] $ServerName,
        [string] $CustomConfigPath = $null,
        [switch] $AllExistingAgents
    )
    $agentsToClean = @($AgentName)
    if ($AllExistingAgents -and -not $CustomConfigPath) {
        $agentsToClean = @($AgentName, 'OpenCode', 'Claude Desktop', 'Claude Code', 'OpenAI Codex', 'Google Antigravity') | Select-Object -Unique
    }

    $updatedFiles = @()
    foreach ($ag in $agentsToClean) {
        $norm = $ag.Trim().ToLowerInvariant()
        if ($norm -match 'opencode') {
            $opencodeExe = Find-OpenCodeCli
            if ($opencodeExe -and -not $CustomConfigPath) {
                try { Invoke-ArchMcpNativeCommand -FilePath $opencodeExe -ArgumentList @('mcp', 'remove', $ServerName, '--global') | Out-Null } catch { }
            }
            $targets = if ($CustomConfigPath) { @($CustomConfigPath) } else { @(Get-ArchMcpAgentConfigTargets -Agent 'opencode') }
            foreach ($t in $targets) {
                if (Remove-OpenCodeMcpServerEntry -ConfigFile $t -ServerName $ServerName) {
                    $updatedFiles += $t
                    Write-ArchOk "Removed '$ServerName' MCP from OpenCode config: $t"
                }
            }
        }
        elseif ($norm -match 'codex') {
            $codexCli = Get-Command 'codex' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($codexCli -and -not $CustomConfigPath) {
                try { Invoke-ArchMcpNativeCommand -FilePath $codexCli.Source -ArgumentList @('mcp', 'remove', $ServerName) | Out-Null } catch { }
            }
            $targets = if ($CustomConfigPath) { @($CustomConfigPath) } else { @(Get-ArchMcpAgentConfigTargets -Agent 'codex') }
            foreach ($t in $targets) {
                if (Remove-CodexMcpServerEntry -ConfigFile $t -ServerName $ServerName) {
                    $updatedFiles += $t
                    Write-ArchOk "Removed '$ServerName' MCP from OpenAI Codex config: $t"
                }
            }
        }
        elseif ($norm -match 'claude desktop') {
            $targets = if ($CustomConfigPath) {
                @($CustomConfigPath)
            } else {
                $t1 = @(Get-ClaudeDesktopConfigTargets | ForEach-Object { $_.Path })
                $t2 = @(Get-ClaudeDesktopConfigPaths)
                @($t1 + $t2 | Select-Object -Unique)
            }
            foreach ($t in $targets) {
                if (Remove-StandardMcpServersJsonEntry -ConfigFile $t -ServerName $ServerName) {
                    $updatedFiles += $t
                    Write-ArchOk "Removed '$ServerName' MCP from Claude Desktop config: $t"
                }
            }
        }
        elseif ($norm -match 'claude code') {
            $claudeCli = Get-Command 'claude' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($claudeCli -and -not $CustomConfigPath) {
                try { Invoke-ArchMcpNativeCommand -FilePath $claudeCli.Source -ArgumentList @('mcp', 'remove', '--scope', 'user', $ServerName) | Out-Null } catch { }
            }
            $targets = if ($CustomConfigPath) { @($CustomConfigPath) } else { @(Get-ArchMcpAgentConfigTargets -Agent 'claude code') }
            foreach ($t in $targets) {
                if (Remove-StandardMcpServersJsonEntry -ConfigFile $t -ServerName $ServerName) {
                    $updatedFiles += $t
                    Write-ArchOk "Removed '$ServerName' MCP from Claude Code config: $t"
                }
            }
        }
        elseif ($norm -match 'antigravity') {
            $targets = if ($CustomConfigPath) { @($CustomConfigPath) } else { @(Get-ArchMcpAgentConfigTargets -Agent 'antigravity') }
            foreach ($t in $targets) {
                if (Remove-StandardMcpServersJsonEntry -ConfigFile $t -ServerName $ServerName) {
                    $updatedFiles += $t
                    Write-ArchOk "Removed '$ServerName' MCP from Google Antigravity config: $t"
                }
            }
        }
    }

    return [pscustomobject]@{
        ServerName   = $ServerName
        UpdatedFiles = @($updatedFiles | Select-Object -Unique)
    }
}

function Stop-ArchMcpIntegrationProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $IntegrationDir
    )
    if (-not $IntegrationDir -or -not (Test-Path -LiteralPath $IntegrationDir)) { return }
    try {
        $normDir = [System.IO.Path]::GetFullPath($IntegrationDir).TrimEnd('\', '/')
        $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            ($_.Name -match '^(python|pythonw|uv|uvx)(\.exe)?$' -or $_.Name -match 'mcp') -and
            (($_.CommandLine -and $_.CommandLine.IndexOf($normDir, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
             ($_.ExecutablePath -and $_.ExecutablePath.IndexOf($normDir, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))
        })
        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
                Write-ArchOk "Stopped running MCP process PID $($p.ProcessId) ($($p.Name))."
            } catch { }
        }
    } catch { }
}

function Remove-ArchMcpDirectorySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $TargetPath
    )
    if (-not (Test-Path -LiteralPath $TargetPath)) { return }
    try {
        Remove-Item -LiteralPath $TargetPath -Recurse -Force -ErrorAction Stop
    } catch {
        # If a binary in .venv is still held by an external process, remove all non-locked source files so status probes report Untested
        Get-ChildItem -LiteralPath $TargetPath -Force -Recurse -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue } catch { }
            }
        try { Remove-Item -LiteralPath $TargetPath -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

function Test-TcpPortListening {
    [CmdletBinding()]
    param(
        [string] $HostAddress = '127.0.0.1',
        [int] $Port,
        [int] $TimeoutMs = 2000
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostAddress, $Port, $null, $null)
        $wait = $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $wait) { return $false }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        try { $client.Close() } catch { }
    }
}

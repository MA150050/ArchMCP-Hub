# ArchMCP Hub - Rhino 7 environment tests (REAL uv + pypi): unsatisfiable upstream pins, pinned Python, both MCP protocol eras.
# Usage: pwsh -File test_rhino_env.ps1 -RhinoDir <clone of reer-ide/rhino_mcp v0.1.10>
param([Parameter(Mandatory)][string]$RhinoDir)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\ArchMCP-Common.ps1')
$script:fail = 0
function Check($name, $cond) { if ($cond) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ } }
$uv = (Get-Command uv).Source
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('archmcp-rh-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item -Recurse -LiteralPath $RhinoDir -Destination "$work/rh" -Exclude '.venv'
if (Test-Path "$work/rh/.venv") { Remove-Item -Recurse -Force "$work/rh/.venv" }
$proj = "$work/rh"
$shim = Join-Path $PSScriptRoot '..\scripts\shims\archmcp_mcp2_entry.py'

# plain `uv sync` must fail on this upstream (documents why the installer cannot use it)
$sync = Invoke-ArchMcpNativeCommand -FilePath $uv -ArgumentList @('sync', '--project', $proj)
Check 'upstream plain uv sync is unsatisfiable (reason for pip-based env)' ($sync.ExitCode -ne 0)
if (Test-Path "$proj/.venv") { Remove-Item -Recurse -Force "$proj/.venv" }

# main env: mcp 1.x, Python 3.12
$py = Initialize-ArchMcpPipEnv -UvExe $uv -ProjectDir $proj -EnvName '.venv' -PythonVersion '3.12' -OverrideLines @('anyio>=4.5', 'mcp[cli]>=1.3.0,<2')
$ver = ((& $py -c "import sys;print('%d.%d' % sys.version_info[:2])") | Out-String).Trim()
$mcpv = ((& $py -c "import importlib.metadata as m;print(m.version('mcp'))") | Out-String).Trim()
Check "main env pinned to Python 3.12 (got $ver)" ($ver -eq '3.12')
Check "main env uses mcp 1.x (got $mcpv)" ($mcpv -like '1.*')
$h1 = Test-ArchMcpStdioHandshake -Command $py -Arguments @((Join-Path $proj 'main.py')) -EnvironmentVariables @{ RHINO_MCP_HOST = '127.0.0.1' } -TimeoutSec 60
Check "main env legacy handshake OK ($($h1.ToolCount) tools)" ($null -eq $h1.Error -and $h1.ToolCount -gt 0)

# rerun is idempotent and a wrong-Python venv is recreated
$py2 = Initialize-ArchMcpPipEnv -UvExe $uv -ProjectDir $proj -EnvName '.venv' -PythonVersion '3.12' -OverrideLines @('anyio>=4.5', 'mcp[cli]>=1.3.0,<2')
Check 'rerun reuses the env' ($py2 -eq $py)
$py13 = Initialize-ArchMcpPipEnv -UvExe $uv -ProjectDir $proj -EnvName '.venv' -PythonVersion '3.13' -OverrideLines @('anyio>=4.5', 'mcp[cli]>=1.3.0,<2')
$ver13 = ((& $py13 -c "import sys;print('%d.%d' % sys.version_info[:2])") | Out-String).Trim()
Check 'venv created with a different Python is recreated' ($ver13 -eq '3.13')

# modern env: mcp 2.x + compat entry, both protocol eras
$pm = Initialize-ArchMcpPipEnv -UvExe $uv -ProjectDir $proj -EnvName '.venv-modern' -PythonVersion '3.12' -OverrideLines @('anyio>=4.5')
$a = @($shim, (Join-Path $proj 'main.py'))
$m1 = Test-ArchMcpStdioHandshake -Command $pm -Arguments $a -EnvironmentVariables @{ RHINO_MCP_HOST = '127.0.0.1' } -TimeoutSec 60 -Modern
$m2 = Test-ArchMcpStdioHandshake -Command $pm -Arguments $a -EnvironmentVariables @{ RHINO_MCP_HOST = '127.0.0.1' } -TimeoutSec 60
Check "modern env: server/discover OK ($($m1.ToolCount) tools)" ($null -eq $m1.Error -and $m1.ToolCount -gt 0)
Check "modern env: legacy initialize OK ($($m2.ToolCount) tools)" ($null -eq $m2.Error -and $m2.ToolCount -gt 0)
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
Write-Host ("`nFailures: $script:fail") -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $script:fail

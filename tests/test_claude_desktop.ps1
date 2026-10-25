# ArchMCP Hub - Claude Desktop registration tests (isolated logic + REAL stdio handshake against synced upstream servers).
# Usage: pwsh -File test_claude_desktop.ps1 -RevitDir <synced revit-mcp-server> -AutoCadDir <synced Autocad-MCP>
# Fixtures create <dir>/.venv/Scripts/{python.exe, autocad-mcp.exe} links only when missing (Linux CI); on Windows the real venv is used.
param([Parameter(Mandatory)][string]$RevitDir, [Parameter(Mandatory)][string]$AutoCadDir, [string]$RevitModernDir = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\ArchMCP-Common.ps1')
$script:fail = 0
function Check($name, $cond) { if ($cond) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ } }

foreach ($d in @($RevitDir, $AutoCadDir)) {
    $sc = Join-Path $d '.venv/Scripts'
    if (-not (Test-Path (Join-Path $sc 'python.exe')) -and (Test-Path (Join-Path $d '.venv/bin/python'))) {
        New-Item -ItemType Directory -Force $sc | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $sc 'python.exe') -Target (Resolve-Path (Join-Path $d '.venv/bin/python')) | Out-Null
        if (Test-Path (Join-Path $d '.venv/bin/autocad-mcp')) { New-Item -ItemType SymbolicLink -Path (Join-Path $sc 'autocad-mcp.exe') -Target (Resolve-Path (Join-Path $d '.venv/bin/autocad-mcp')) | Out-Null }
    }
}
$uvFake = (Get-Command uv -ErrorAction SilentlyContinue).Source
if (-not $uvFake) { $uvFake = (Join-Path $RevitDir '.venv/Scripts/python.exe') }
$revitArgs = @('run', '--directory', $RevitDir, 'main.py'); $revitEnv = @{ REVIT_HOST = '127.0.0.1'; REVIT_PORT = '48884' }
$acadArgs = @('run', '--directory', $AutoCadDir, 'autocad-mcp'); $acadEnv = @{ AUTOCAD_MCP_BACKEND = 'auto'; ALLOWED_PATHS = [System.IO.Path]::GetTempPath(); TOOL_PROFILE = 'full'; TOOL_PACKS = 'core,arch,settings'; DANGEROUS_COMMANDS_ENABLED = 'false' }

function New-Sandbox { $r = Join-Path ([System.IO.Path]::GetTempPath()) ('archmcp-t-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force "$r/Roaming/Claude", "$r/Local/Packages" | Out-Null; $env:APPDATA = "$r/Roaming"; $env:LOCALAPPDATA = "$r/Local"; return $r }

# T1 launch spec: direct venv, no uv at startup
$s = Get-ArchMcpClaudeLaunchSpec -Command $uvFake -Arguments $revitArgs -EnvironmentVariables $revitEnv
Check 'launch spec (Revit) resolves direct venv python' ($s.Direct -and $s.Command -match 'python\.exe$' -and $s.Arguments[0] -match 'main\.py$' -and $s.Env.PYTHONUTF8 -eq '1')
$s2 = Get-ArchMcpClaudeLaunchSpec -Command $uvFake -Arguments $acadArgs -EnvironmentVariables $acadEnv
Check 'launch spec (AutoCAD) resolves console-script exe' ($s2.Direct -and $s2.Command -match 'autocad-mcp\.exe$' -and $s2.Arguments.Count -eq 0)
$s3 = Get-ArchMcpClaudeLaunchSpec -Command $uvFake -Arguments @('run', '--directory', (Join-Path $RevitDir 'nope'), 'main.py')
Check 'launch spec falls back when venv missing' (-not $s3.Direct -and $s3.Command -eq $uvFake)

# T2 fresh + preserve + idempotent + real handshake (Revit and AutoCAD)
$r = New-Sandbox; $cfg = "$r/Roaming/Claude/claude_desktop_config.json"
'{"theme":"dark","mcpServers":{"other":{"command":"node","args":["x.js"]}}}' | Set-Content $cfg
$o1 = Register-ArchMcpWithClaudeDesktop -ServerName 'revit' -Command $uvFake -Arguments $revitArgs -EnvironmentVariables $revitEnv
$o2 = Register-ArchMcpWithClaudeDesktop -ServerName 'autocad' -Command $uvFake -Arguments $acadArgs -EnvironmentVariables $acadEnv
$o3 = Register-ArchMcpWithClaudeDesktop -ServerName 'revit' -Command $uvFake -Arguments $revitArgs -EnvironmentVariables $revitEnv
$j = Get-Content $cfg -Raw | ConvertFrom-Json
$names = @($j.mcpServers.PSObject.Properties.Name)
Check 'unrelated server and top-level keys preserved' ($j.theme -eq 'dark' -and $names -contains 'other')
Check 'revit + autocad registered, no duplicates after rerun' (($names | Where-Object { $_ -eq 'revit' }).Count -eq 1 -and $names -contains 'autocad' -and $names.Count -eq 3)
Check 'args stay JSON arrays' ($j.mcpServers.revit.args -is [array] -and $j.mcpServers.revit.env.REVIT_PORT -eq '48884')
Check 'file has no UTF-8 BOM' ([System.IO.File]::ReadAllBytes($cfg)[0] -eq 0x7B)
Check 'backups were created' (@(Get-ChildItem "$r/Roaming/Claude" -Filter '*.backup-*').Count -ge 1)

# T3 Store package present, no config in package -> seeded from %APPDATA%, effective file valid
$r = New-Sandbox; $cfg = "$r/Roaming/Claude/claude_desktop_config.json"
'{"mcpServers":{"keep":{"command":"c"}}}' | Set-Content $cfg
New-Item -ItemType Directory -Force "$r/Local/Packages/Claude_abc123" | Out-Null
$null = Register-ArchMcpWithClaudeDesktop -ServerName 'revit' -Command $uvFake -Arguments $revitArgs -EnvironmentVariables $revitEnv -SkipHandshake
$store = Get-Content "$r/Local/Packages/Claude_abc123/LocalCache/Roaming/Claude/claude_desktop_config.json" -Raw | ConvertFrom-Json
Check 'Store config seeded (existing servers kept) and contains revit' (($store.mcpServers.PSObject.Properties.Name -contains 'keep') -and ($store.mcpServers.PSObject.Properties.Name -contains 'revit'))

# T4 malformed existing JSON -> abort, original untouched
$r = New-Sandbox; $cfg = "$r/Roaming/Claude/claude_desktop_config.json"; '{ broken' | Set-Content $cfg; $before = Get-Content $cfg -Raw
$threw = $false; try { Register-ArchMcpWithClaudeDesktop -ServerName 'revit' -Command $uvFake -Arguments $revitArgs -EnvironmentVariables $revitEnv -SkipHandshake | Out-Null } catch { $threw = $true }
Check 'malformed JSON aborts and leaves file untouched' ($threw -and ((Get-Content $cfg -Raw) -eq $before))

# T5 handshake failure -> full rollback (existing file restored; new file removed)
$r = New-Sandbox; $cfg = "$r/Roaming/Claude/claude_desktop_config.json"; '{"mcpServers":{"keep":{"command":"c"}}}' | Set-Content $cfg; $before = Get-Content $cfg -Raw
$bad = Join-Path $r 'bad.py'; 'import sys; sys.exit(3)' | Set-Content $bad
$threw = $false; try { Register-ArchMcpWithClaudeDesktop -ServerName 'broken' -Command (Join-Path $RevitDir '.venv/Scripts/python.exe') -Arguments @($bad) -EnvironmentVariables @{} | Out-Null } catch { $threw = $true; $msg = $_.Exception.Message }
Check 'failing server is rejected and config restored byte-for-byte' ($threw -and ((Get-Content $cfg -Raw) -eq $before) -and $msg -match 'rolled back')


# T6 Claude Desktop 3.x layout: Local\Claude-Data\claude_<family> is the ONLY target; seeded from older config; legacy files untouched
$r = New-Sandbox; $cfg = "$r/Roaming/Claude/claude_desktop_config.json"
'{"mcpServers":{"keep":{"command":"c"}}}' | Set-Content $cfg; $legacyBefore = Get-Content $cfg -Raw
New-Item -ItemType Directory -Force "$r/Local/Claude-Data/claude_pzs8sxrjxfjjc", "$r/Local/Packages/Claude_pzs8sxrjxfjjc" | Out-Null
$o = Register-ArchMcpWithClaudeDesktop -ServerName 'revit' -Command $uvFake -Arguments $revitArgs -EnvironmentVariables $revitEnv -SkipHandshake
$cd = Get-Content "$r/Local/Claude-Data/claude_pzs8sxrjxfjjc/claude_desktop_config.json" -Raw | ConvertFrom-Json
Check 'Claude-Data config written, seeded, contains revit' (($cd.mcpServers.PSObject.Properties.Name -contains 'keep') -and ($cd.mcpServers.PSObject.Properties.Name -contains 'revit'))
Check 'only Claude-Data target used; legacy untouched' ($o.ConfigPaths.Count -eq 1 -and $o.ConfigPath -match 'Claude-Data' -and ((Get-Content $cfg -Raw) -eq $legacyBefore))

# T7 agent config path resolution (flexible, env overrides, existing files win)
$h = Join-Path ([System.IO.Path]::GetTempPath()) ('archmcp-h-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $h | Out-Null; $env:USERPROFILE = $h
foreach ($v in 'CODEX_HOME','CLAUDE_CONFIG_DIR','OPENCODE_CONFIG','XDG_CONFIG_HOME') { Remove-Item "env:$v" -ErrorAction SilentlyContinue }
Check 'antigravity default (nothing exists) = .gemini/config' (@(Get-ArchMcpAgentConfigTargets -Agent 'Google Antigravity')[0].Replace('\','/') -like '*/.gemini/config/mcp_config.json')
New-Item -ItemType Directory -Force "$h/.gemini/antigravity" | Out-Null
Check 'antigravity uses legacy folder when only it exists' (@(Get-ArchMcpAgentConfigTargets -Agent 'Google Antigravity')[0].Replace('\','/') -like '*/.gemini/antigravity/mcp_config.json')
New-Item -ItemType Directory -Force "$h/.gemini/config" | Out-Null; '{}' | Set-Content "$h/.gemini/config/mcp_config.json"; '{}' | Set-Content "$h/.gemini/antigravity/mcp_config.json"
$ag = @(Get-ArchMcpAgentConfigTargets -Agent 'Google Antigravity')
Check 'antigravity returns both existing files, config first' ($ag.Count -eq 2 -and $ag[0] -match 'config[/\\]mcp_config\.json$')
$null = Register-ArchMcpWithAgent -AgentName 'Google Antigravity' -ServerName 'revit' -Command $uvFake -Arguments $revitArgs -EnvironmentVariables $revitEnv
Check 'antigravity registration wrote revit to both existing files' ((Get-Content "$h/.gemini/config/mcp_config.json" -Raw) -match 'revit' -and (Get-Content "$h/.gemini/antigravity/mcp_config.json" -Raw) -match 'revit')
$env:CODEX_HOME = "$h/cx"; Check 'codex honors CODEX_HOME' (@(Get-ArchMcpAgentConfigTargets -Agent 'OpenAI Codex')[0].Replace('\','/') -like '*/cx/config.toml')
$env:CLAUDE_CONFIG_DIR = "$h/cc"; Check 'claude code honors CLAUDE_CONFIG_DIR' (@(Get-ArchMcpAgentConfigTargets -Agent 'Claude Code')[0].Replace('\','/') -like '*/cc/.claude.json')
$env:OPENCODE_CONFIG = "$h/oc.json"; Check 'opencode honors OPENCODE_CONFIG, keeps default as fallback' (@(Get-ArchMcpAgentConfigTargets -Agent 'OpenCode')[0].Replace('\','/') -like '*/oc.json')
Remove-Item env:OPENCODE_CONFIG; Check 'opencode default unchanged (.config/opencode/opencode.json)' (@(Get-ArchMcpAgentConfigTargets -Agent 'OpenCode')[0].Replace('\','/') -like '*/.config/opencode/opencode.json')

# T8 Antigravity registers the DIRECT venv launcher (not uv); failing server leaves config untouched
$agCfg = "$h/.gemini/config/mcp_config.json"
$j = Get-Content $agCfg -Raw | ConvertFrom-Json
Check 'antigravity entry uses direct venv python (no uv)' ($j.mcpServers.revit.command -match 'python\.exe$' -and $j.mcpServers.revit.args[0] -match 'main\.py$' -and $j.mcpServers.revit.env.PYTHONUTF8 -eq '1')
$before = Get-Content $agCfg -Raw
$threw = $false; try { Register-ArchMcpWithAgent -AgentName 'Google Antigravity' -ServerName 'broken' -Command $uvFake -Arguments @('run','--directory',$RevitDir,'nonexistent_entry.py') -EnvironmentVariables @{} | Out-Null } catch { $threw = $true }
Check 'antigravity: missing script falls back to original command (no crash)' (-not $threw)

# T9 MCP 2026-07-28 (server/discover): v1 SDK server fails the modern probe; same server on SDK 2.x via the compat entry passes both eras
$shim = Join-Path $PSScriptRoot '..\scripts\shims\archmcp_mcp2_entry.py'
Check 'v1-SDK Revit server FAILS modern probe (reproduces the Antigravity hang)' ((Test-ArchMcpStdioHandshake -Command (Join-Path $RevitDir '.venv/Scripts/python.exe') -Arguments @((Join-Path $RevitDir 'main.py')) -EnvironmentVariables $revitEnv -TimeoutSec 15 -Modern).Error -ne $null)
if ($RevitModernDir) {
    $mpy = Join-Path $RevitModernDir '.venv/bin/python'; if (-not (Test-Path $mpy)) { $mpy = Join-Path $RevitModernDir '.venv/Scripts/python.exe' }
    $m1 = Test-ArchMcpStdioHandshake -Command $mpy -Arguments @($shim, (Join-Path $RevitModernDir 'main.py')) -EnvironmentVariables $revitEnv -TimeoutSec 60 -Modern
    Check 'MCP 2.x + compat entry: server/discover OK with 48 tools' ($null -eq $m1.Error -and $m1.ToolCount -eq 48)
    $m2 = Test-ArchMcpStdioHandshake -Command $mpy -Arguments @($shim, (Join-Path $RevitModernDir 'main.py')) -EnvironmentVariables $revitEnv -TimeoutSec 60
    Check 'MCP 2.x + compat entry: legacy initialize still OK with 48 tools' ($null -eq $m2.Error -and $m2.ToolCount -eq 48)
    $r = New-Sandbox; $env:USERPROFILE = $r; New-Item -ItemType Directory -Force "$r/.gemini/config" | Out-Null; '{}' | Set-Content "$r/.gemini/config/mcp_config.json"
    $null = Register-ArchMcpWithAgent -AgentName 'Google Antigravity' -ServerName 'revit' -Command $mpy -Arguments @($shim, (Join-Path $RevitModernDir 'main.py')) -EnvironmentVariables $revitEnv
    $j = Get-Content "$r/.gemini/config/mcp_config.json" -Raw | ConvertFrom-Json
    Check 'Antigravity registers the MCP 2.x launcher (python + shim + main.py)' ($j.mcpServers.revit.command -eq $mpy -and $j.mcpServers.revit.args.Count -eq 2 -and $j.mcpServers.revit.args[0] -match 'archmcp_mcp2_entry\.py$')
}

Write-Host ("`nFailures: $script:fail") -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $script:fail

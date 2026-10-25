# ArchMCP Hub 1.2.0 - SketchUp MCP Fix & Universal Disable/Uninstall

## 1. SketchUp MCP Fixes
- **Fixed SketchUp Ruby Extension Loading Error (`Error Loading File su_mcp/main` / `Could not find included file 'su_mcp/main'`)**:
  - Upstream `NeoNexAI/sketchup-mcp` and `mhyrr/sketchup-mcp` package the Ruby extension inside `su_mcp/su_mcp.rb` and `su_mcp/su_mcp/main.rb` (alongside `su_mcp/package.rb`).
  - Previously, copying `$repoDir\su_mcp` directly into `%APPDATA%\SketchUp\SketchUp 20XX\SketchUp\Plugins\su_mcp` nested `main.rb` one folder too deep (`Plugins\su_mcp\su_mcp\main.rb`), causing SketchUp to fail when loading `su_mcp/main`.
  - `Resolve-SketchUpRubyPluginSource` now automatically detects both nested (`su_mcp/su_mcp/main.rb`) and flat (`su_mcp/main.rb`) repository layouts, deploys `su_mcp.rb` and `su_mcp/main.rb` to the exact paths required by SketchUp, removes any stale nested `Plugins\su_mcp\su_mcp` or `.backup-*` artifacts, and verifies `Plugins\su_mcp\main.rb` on disk.
- **Fixed OpenCode & Agent MCP Spawn Failure (`Failed to spawn: neonexai-sketchup-mcp` / `cause: program not found`)**:
  - Previously, `Install-SketchUp-MCP.ps1` registered `uv run --directory <repo> neonexai-sketchup-mcp`, which exited with code 2 (`program not found`) when the console script name in `pyproject.toml` differed (`sketchup-mcp`) or was not installed into `.venv\Scripts`, and was vulnerable to `mcp 2.x` breaking `mcp.server.fastmcp` imports.
  - `Install-SketchUp-MCP.ps1` now builds a pinned Python 3.12 virtual environment via `Initialize-ArchMcpPipEnv` (`mcp[cli]>=1.3.0,<2` and `anyio>=4.5` for OpenCode, Claude Desktop, Claude Code, and OpenAI Codex; `.venv-modern` with `archmcp_mcp2_entry.py` for Google Antigravity), installs the package in editable mode, generates `archmcp_sketchup_server.py` (including a `FastMCP.__init__` `description` keyword compatibility shim), verifies the stdio handshake (`initialize` + `tools/list`), and registers the `.venv` Python interpreter directly.

## 2. Disable / Uninstall Action Across All Hosts & Agents
- Added the **Disable / Uninstall** (`تعطيل / إلغاء تثبيت`) button next to **Install & connect** in the main Integrations bar.
- Added `Unregister-ArchMcpFromAgent`, `Stop-ArchMcpIntegrationProcesses`, and `Remove-ArchMcpDirectorySafe` in `scripts/ArchMCP-Common.ps1` and `-Action Uninstall` across `Install-Integration.ps1` and all five host scripts (`Revit`, `Rhino`, `3ds Max`, `AutoCAD`, `SketchUp`).
- Automatically refreshes the UI environment status when any PowerShell action window closes.

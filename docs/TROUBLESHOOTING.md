# ArchMCP Hub v1.0.0 — Troubleshooting Guide (دليل استكشاف الأخطاء وإصلاحها)

This guide covers common installation, configuration, and runtime scenarios across all 5 supported engineering host applications and 5 AI clients.

---

## 1. Understanding Status Badges (`Installed (Awaiting Host)` vs. `Verified (Live)`)

### Symptom
After clicking **Install & connect**, the PowerShell window completes with exit code `0`, but the status column in ArchMCP Hub displays **`Installed (Awaiting Host)`** (`Installed (بانتظار البرنامج)`) instead of **`Verified (Live)`**.

### Cause
This is **normal behavior** when the target engineering software (Revit, Rhino, 3ds Max, AutoCAD, or SketchUp) is closed or its in-process bridge has not been started yet. ArchMCP Hub never reports `Verified (Live)` unless the live local port/pipe/COM endpoint actively responds.

### Solution
1. Open the target CAD/BIM application and activate its listener:
   - **Revit (2022–2027)**: Open a `.rvt` project document. If Revit was already open during installation, click **pyRevit → Reload** so Routes starts on port `48884`.
   - **Rhino 8**: Type `mcpstart` in the Rhino 8 command line (port `1999`).
   - **Rhino 7**: Run `%APPDATA%\McNeel\Rhinoceros\7.0\scripts\rhino_mcp_bridge.py` via **Tools → PythonScript → Run...**.
   - **3ds Max (2021–2027)**: Restart 3ds Max so `mcp_server.ms` / `mcp_bridge.gup` loads automatically on startup (port `8765` / Named Pipe).
   - **AutoCAD (2021–2027)**: Open AutoCAD with an active drawing (no modal dialog open) for live ActiveX/COM. *(Note: Headless DXF tools work even while AutoCAD is closed.)*
   - **SketchUp (2021–2026)**: Open SketchUp and select **Extensions → SketchUp MCP → Start Server** (port `9876`).
2. Click **Verify** (`فحص`) or **Check environment** (`فحص البيئة`) in ArchMCP Hub.

---

## 2. Per-Application Troubleshooting

### A. Autodesk Revit (2022 – 2027)

- **Issue: `http://127.0.0.1:48884/revit_mcp/status/` is unreachable or returns HTTP 404**:
  1. Ensure **[pyRevit](https://github.com/pyrevitlabs/pyRevit/releases/latest)** (`v4.8.16+` or `v5.x`) is installed.
  2. Open `%APPDATA%\pyRevit\pyRevit_config.ini` and verify that the installer set:
     ```ini
     [routes]
     enabled = true
     port = 48884
     core_api = true
     ```
     and that `[core]` includes `"%APPDATA%\pyRevit\Extensions"` in `userextensions`.
  3. Restart Revit completely (pyRevit starts the Routes HTTP server during Revit startup), open a project model, and click **Verify** in ArchMCP Hub.
- **Issue: Revit 2022 or 2023 `ElementId.Value` AttributeError in third-party scripts**:
  - Revit 2022–2023 uses 32-bit `ElementId.IntegerValue`, whereas Revit 2024+ uses 64-bit `ElementId.Value`. ArchMCP Hub's `Apply-Revit2022CompatibilityPatch` automatically patches `.Id.Value` calls inside `%APPDATA%\pyRevit\Extensions\revit-mcp.extension\revit_mcp\`. If you manually replaced files in the extension folder, click **Repair** in ArchMCP Hub to re-apply the compatibility shim.

### B. Rhinoceros 3D (Rhino 7 & Rhino 8)

- **Issue: Rhino 8 TCP port `1999` is not listening**:
  1. Open Rhino 8 and run the command `mcpstart`. (To stop the listener, run `mcpstop`.)
  2. Ensure only **one** AI client is connected to the Rhino TCP bridge at a time.
- **Issue: Rhino 7 dependency conflict (`anyio<4` vs `mcp>=1.3.0`) or Python 3.14 wheel failure**:
  - Upstream `reer-ide/rhino_mcp` pins `anyio<4` in `pyproject.toml`, which fails with plain `uv sync`. ArchMCP Hub's `Install-Rhino-MCP.ps1` automatically bypasses `uv sync` using `Initialize-ArchMcpPipEnv` with pinned **Python 3.12** and `--override` (`anyio>=4.5`, `mcp[cli]>=1.3.0,<2`). If an older virtual environment exists, click **Repair** to recreate it cleanly.

### C. Autodesk 3ds Max (2021 – 2027)

- **Issue: 3ds Max bridge does not respond on TCP `8765` or Named Pipe**:
  1. Close 3ds Max before running **Install & connect** or **Repair** so locked `.gup` files do not block updates.
  2. Verify that `%LOCALAPPDATA%\Autodesk\3dsMax\<YEAR> - 64bit\ENU\scripts\startup\mcp_server.ms` and `%LOCALAPPDATA%\3dsmax-mcp\mcp_config.ini` exist.
  3. Start 3ds Max and click **Verify**.

### D. Autodesk AutoCAD (2021 – 2027)

- **Issue: AutoCAD live COM reports inactive even though AutoCAD is open**:
  - Ensure AutoCAD has finished loading its startup screen, has an active drawing tab open, and does not have an active command prompt or modal dialog blocking COM (`AutoCAD.Application`).
- **Issue: File access denied outside `Documents\AutoCAD`**:
  - By default, ArchMCP Hub scopes `ALLOWED_PATHS` to `%USERPROFILE%\Documents\AutoCAD` and sets `DANGEROUS_COMMANDS_ENABLED=false` for security. You can place target `.dwg`/`.dxf` files inside `Documents\AutoCAD` or adjust `ALLOWED_PATHS` in your AI client's MCP configuration.

### E. SketchUp (2021 – 2026)

- **Issue: SketchUp shows `Error Loading File su_mcp/main: Could not find included file 'su_mcp/main'`**:
  - Caused by older manual installations copying `su_mcp/` with an extra nested subfolder (`Plugins\su_mcp\su_mcp\main.rb`) or leaving `.backup-*` folders inside SketchUp's `Plugins` folder.
  - **Fix**: Click **Repair** in ArchMCP Hub v1.0.0. `Resolve-SketchUpRubyPluginSource` cleans any stray `.backup-*` items and deploys `su_mcp.rb` and `su_mcp\main.rb` to the exact paths required by SketchUp (`%APPDATA%\SketchUp\SketchUp 20XX\SketchUp\Plugins\`).
- **Issue: OpenCode or AI client reports `Failed to spawn: neonexai-sketchup-mcp` (`program not found`)**:
  - **Fix**: Click **Repair** in ArchMCP Hub v1.0.0. The installer now builds a pinned Python 3.12 virtual environment and registers the direct `.venv\Scripts\python.exe` interpreter with `archmcp_sketchup_server.py`, verifying the `stdio` handshake before writing your agent configuration.

---

## 3. Per-AI Client Troubleshooting

### A. Claude Desktop Shows No MCP Tools
1. **Perform a Full Quit from the Windows System Tray**:
   Closing the Claude Desktop window only minimizes it to the tray. Right-click the Claude icon in the Windows system tray (bottom-right taskbar) and click **Quit**, then reopen Claude Desktop.
2. **Verify Claude Desktop 3.x (MSIX) vs. Standard Config Path**:
   - Claude Desktop 3.x (Microsoft Store MSIX) reads:
     ```text
     %LOCALAPPDATA%\Claude-Data\claude_<family>\claude_desktop_config.json
     ```
     (You can confirm the active path inside Claude Desktop via **Settings → Developer → Edit Config**.)
   - Older Store builds read `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude_desktop_config.json`, and standard desktop builds read `%APPDATA%\Claude\claude_desktop_config.json`.
   - ArchMCP Hub v1.0.0 (`Get-ClaudeDesktopConfigTargets`) automatically detects `Claude-Data\claude_*` first, seeds it from any existing config so you never lose existing servers, writes strict **UTF-8 without BOM**, and runs a real `stdio` handshake (`initialize` + `tools/list`) before saving.

### B. Google Antigravity Shows Server Stuck on "Connecting" or Red Error (`server/discover`)
- **Cause**: Current versions of Google Antigravity use the **MCP `2026-07-28` stateless discovery protocol** (`server/discover` with `_meta`), whereas upstream FastMCP v1 servers (`revit-mcp-server`, `reer-ide/rhino_mcp`, `sketchup-mcp`) use MCP Python SDK 1.x, which hangs or fails validation on `server/discover`.
- **How ArchMCP Hub v1.0.0 Solves This**:
  - For **Revit**, **Rhino 7**, and **SketchUp**, selecting **Google Antigravity** automatically creates a separate `.venv-modern` virtual environment (`mcp>=2,<3`) and launches the unmodified upstream server through `scripts\shims\archmcp_mcp2_entry.py`, verifying both `2026-07-28` (`server/discover`) and legacy `initialize` handshakes before updating `~/.gemini/config/mcp_config.json`.
- **Known Limitation for AutoCAD + Google Antigravity**:
  - Upstream `U-C4N/Autocad-MCP` depends on `fastmcp 3.x` internals (`fastmcp.tools.tool`), which currently rejects `server/discover` and cannot yet run under `mcp 2.x`. Use **OpenCode** or **Claude Desktop** for AutoCAD MCP Pro until upstream updates its SDK dependency.

---

## 4. Inspecting Logs & Restoring Backups

- **Logs Location**: `%LOCALAPPDATA%\ArchMCP Hub\Logs\` (accessible via **Activity & Logs → Open diagnostic log folder** in the UI).
- **Automatic Backups**: Whenever ArchMCP Hub modifies a configuration file or plugin directory, it creates a sibling `.backup-YYYYMMDD-HHMMSS` file or directory. If any installation step or handshake fails, the `trap` handler in the PowerShell script automatically rolls back all modified paths via `Restore-ArchMcpBackup`.

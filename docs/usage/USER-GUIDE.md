# ArchMCP Hub v1.0.0 — Step-by-Step User Guide

This guide walks through every feature of the **ArchMCP Hub v1.0.0** desktop control center and explains how to install, connect, disable/uninstall, repair, and verify MCP integrations across all 5 supported engineering applications and 5 AI clients.

---

## 1. Navigating the Control Center Interface

When `ArchMCP.Hub.exe` opens, it automatically runs an initial environment scan and displays the **Overview** dashboard.

### Top Bar Controls
- **`EN / عربي` (`LanguageButton`)**: Switches the entire interface, status badges, and host activation hints immediately between **English** and **Arabic**.
- **`☼ Light mode` / `◐ Dark mode` (`ThemeButton`)**: Toggles between the default restrained dark engineering palette (`#101318` canvas / `#191E26` panels / `#83D6C4` accent) and high-contrast light mode (`#F3F5F8` canvas / `#FFFFFF` panels / `#087F70` accent).
- **`Check environment` (`CheckEnvironmentButton`)**: Re-scans `Program Files`, `Program Files (x86)`, and Windows Uninstall Registry entries for installed CAD/BIM executables and probes each host's live MCP status.

### Left Sidebar Sections
1. **Overview**: High-level summary of detected host versions, installed integrations, and live-verified connections.
2. **Integrations**: The primary table of detected host applications, version numbers, detection sources, compatibility statuses, AI Agent selector, and action buttons.
3. **AI Agents**: Reference summary of all 5 supported MCP clients and their configuration file locations.
4. **Compatibility**: Explanation of the four evidence-based status tiers (`Verified`, `InstalledAwaitingHost`, `Untested`, `Unsupported`).
5. **Activity & Logs**: Displays the timestamp and summary of the most recent environment scan and provides the **Open diagnostic log folder** button (`%LOCALAPPDATA%\ArchMCP Hub\Logs\`).
6. **Settings**: Quick access to appearance and language toggles.

---

## 2. Step-by-Step Workflow: Connecting a Host to an AI Client

1. **Open the Integrations View**:
   Click **Integrations** (`التكاملات`) in the left sidebar (or click **Open integrations** on the Overview card).
2. **Select Your Engineering Application Version**:
   Click a row in the detected applications list (for example, `Autodesk Revit · 2025.0.0`, `Rhinoceros 3D · 8.0`, `Autodesk 3ds Max · 2024.0.0`, `Autodesk AutoCAD · 2025.0.0`, or `SketchUp · 2025.0.0`).
   - Observe the **Host Activation Hint** directly beneath the selected host name in the bottom action bar.
3. **Select Your Target AI Agent**:
   Use the **AI AGENT** dropdown (`AgentCombo`) to select your client:
   - `OpenAI Codex`
   - `Claude Desktop`
   - `Claude Code`
   - `Google Antigravity`
   - `OpenCode` (selected by default)
4. **Click `Install & connect` (`تثبيت وربط`)**:
   - ArchMCP Hub opens a dedicated Windows PowerShell window and executes `scripts\Install-Integration.ps1` with `-Action Install`.
   - The installer downloads/verifies the upstream MCP repository, sets up the isolated Python virtual environment via `uv`, backs up existing configuration files, deploys the host plugin/bridge, verifies the MCP handshake (where applicable), and merges the server entry into your chosen AI client's configuration.
   - When the operation finishes, review the output in the PowerShell window and press **Enter** to close it. ArchMCP Hub automatically refreshes the table status when the window exits.

---

## 3. Activating the In-Host Bridge & Running `Verify`

After **Install & connect** finishes, if the CAD application is closed, ArchMCP Hub reports **`Installed (Awaiting Host)`**. To reach **`Verified (Live)`**, perform the host-side activation step below and click **`Verify`** (`فحص`):

### A. Autodesk Revit (2022 – 2027)
1. Open Autodesk Revit (2022–2027) and open any `.rvt` project document.
2. If Revit was already open during installation, go to the **pyRevit** ribbon tab and click **Reload** so `revit-mcp.extension` and the Routes HTTP server load on `http://127.0.0.1:48884/revit_mcp/status/`.
3. Return to ArchMCP Hub and click **Verify**. The status changes to **`Verified (Live)`**.

### B. Rhinoceros 3D (Rhino 7 & Rhino 8)
- **Rhino 8**:
  1. Open Rhinoceros 8.
  2. In the Rhino command line, type **`mcpstart`** and press Enter (starts the TCP bridge on `127.0.0.1:1999`).
  3. Click **Verify** in ArchMCP Hub.
- **Rhino 7**:
  1. Open Rhinoceros 7.
  2. Navigate to **Tools → PythonScript → Run...** and select:
     ```text
     %APPDATA%\McNeel\Rhinoceros\7.0\scripts\rhino_mcp_bridge.py
     ```
  3. Click **Verify** in ArchMCP Hub.

### C. Autodesk 3ds Max (2021 – 2027)
1. Start (or restart) Autodesk 3ds Max (2021–2027).
2. The startup MAXScript (`%LOCALAPPDATA%\Autodesk\3dsMax\<YEAR> - 64bit\ENU\scripts\startup\mcp_server.ms`) and/or the 2023+ Global Utility Plugin (`.gup`) automatically starts the local listener (`127.0.0.1:8765` / Named Pipe).
3. Click **Verify** in ArchMCP Hub.

### D. Autodesk AutoCAD (2021 – 2027)
- **Headless DXF Mode**: Works immediately after installation without opening AutoCAD.
- **Live COM Mode (`Verified (Live)`)**:
  1. Open Autodesk AutoCAD (2021–2027) with a drawing open and no modal dialog blocking COM.
  2. Click **Verify** in ArchMCP Hub.

### E. SketchUp (2021 – 2026)
1. Start (or restart) SketchUp (2021–2026).
2. From the top menu bar in SketchUp, select **Extensions → SketchUp MCP → Start Server** (starts the local TCP listener on `127.0.0.1:9876`).
3. Click **Verify** in ArchMCP Hub.

---

## 4. How Each AI Client Is Configured

ArchMCP Hub never overwrites unrelated MCP servers or user preferences in your AI client configuration files:

| AI Client | Configuration Target(s) Updated | Registration Method & Special Handling |
| :--- | :--- | :--- |
| **OpenCode** | `~/.config/opencode/opencode.json` (plus `$env:OPENCODE_CONFIG` and `$env:XDG_CONFIG_HOME/opencode/opencode.json` if set) | Runs `opencode mcp add <name> --global` when CLI is found, and merges `mcp.<name>` (or `mcp.servers.<name>`) in UTF-8 without BOM. |
| **Claude Desktop** | 1. `%LOCALAPPDATA%\Claude-Data\claude_*\claude_desktop_config.json` (Claude Desktop 3.x MSIX)<br>2. `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude_desktop_config.json`<br>3. `%APPDATA%\Claude\claude_desktop_config.json` | Resolves direct `.venv\Scripts\python.exe` (or console-script `.exe`) launcher so `uv run` never times out under MSIX; seeds new MSIX config from `%APPDATA%`; validates `stdio` MCP handshake (`initialize` + `tools/list`) before committing; writes UTF-8 without BOM. **Quit Claude Desktop from the system tray and reopen to load newly registered tools.** |
| **Claude Code** | `~/.claude.json` (or `$env:CLAUDE_CONFIG_DIR/.claude.json`) | Runs `claude mcp add --scope user <name> -- ...` when CLI is installed, and merges `mcpServers.<name>` in JSON. |
| **OpenAI Codex** | `~/.codex/config.toml` (or `$env:CODEX_HOME/config.toml`) | Runs `codex mcp add <name>` when CLI is installed, and merges `[mcp_servers.<name>]` and `[mcp_servers.<name>.env]` sections in TOML. |
| **Google Antigravity** | `~/.gemini/config/mcp_config.json` (and `~/.gemini/antigravity/mcp_config.json` if present) | Uses direct `.venv` Python launcher; for FastMCP v1 servers (Revit, Rhino 7, SketchUp), provisions a dedicated `.venv-modern` (`mcp>=2,<3`) and launches via `archmcp_mcp2_entry.py` so both `2026-07-28` (`server/discover`) and legacy `initialize` protocols succeed. |

---

## 5. Using `Repair` and `Disable / Uninstall`

- **`Repair` (`إصلاح`)**:
  Re-synchronizes the repository and Python virtual environment, re-deploys the host plugin/bridge files (creating a fresh timestamped backup), and re-validates the AI client configuration.
- **`Disable / Uninstall` (`تعطيل / إلغاء تثبيت`)**:
  1. Removes the server entry (`revit`, `rhino`, `3dsmax-mcp`, `autocad`, or `sketchup`) from the selected AI client configuration **and** all other existing AI client configuration files on disk (`-AllExistingAgents`).
  2. Stops any running Python/MCP background processes associated with that integration (`Stop-ArchMcpIntegrationProcesses`).
  3. Removes the deployed host plugin/extension/startup script (`revit-mcp.extension`, `rhinomcp` Yak package / `rhino_mcp_bridge.py`, `mcp_server.ms`, `su_mcp.rb` + `su_mcp/`) and cleans up the local integration directory.
  4. Automatically refreshes the UI table back to `Untested (Ready to install)`.

---

## 6. Running Installer Scripts Directly from PowerShell (CLI Mode)

Power users and administrators can also invoke the unified dispatcher directly from Windows PowerShell 5.1+:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-Integration.ps1 `
  -HostId revit `
  -HostVersion "2025.0.0" `
  -AgentName "Claude Desktop" `
  -Action Install
```

Supported `-Action` values: `Install`, `Repair`, `Verify`, `Uninstall` (add `-NonInteractive` for automated scripts so the window does not wait for `Read-Host`).

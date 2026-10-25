# ArchMCP Hub v1.0.0 — Installation Guide

This document provides complete installation and setup instructions for **ArchMCP Hub v1.0.0**, including workstation requirements, one-click launcher execution, local toolchain bootstrapping, and per-host prerequisites.

---

## 1. System Requirements

### Operating System & Shell
- **Operating System**: Windows 10 or Windows 11 (64-bit / `win-x64`).
- **PowerShell**: Windows PowerShell 5.1 (included by default in Windows 10/11) or PowerShell 7+.
  - All ArchMCP Hub scripts under `scripts/` are strictly 7-bit ASCII clean and declare `#Requires -Version 5.1`, ensuring zero encoding errors on standard Windows systems.
- **Permissions**: Standard user account (`requiresElevation: false`). Administrator privileges are **not** required to run ArchMCP Hub or install MCP bridges into user-local paths.

### .NET Runtime & SDK
- **Target Framework**: `.NET 10.0` (`net10.0-windows` for the WPF application, `net10.0` for `ArchMCP.Hub.Core`).
- **Automatic Local Bootstrap**: If `.NET SDK` (`8.0`, `9.0`, or `10.0`) is not installed globally on your machine, running `Run-ArchMCP-Hub.bat` (`scripts/Setup-And-Run.ps1`) automatically downloads Microsoft's official `dotnet-install.ps1` script and installs an isolated local copy into `.tools\dotnet\` inside the project folder.

### Python & Package Manager (`uv` / `uvx`)
- **Astral `uv` / `uvx`**: Automatically bootstrapped by `Ensure-UvExecutable` (`scripts/ArchMCP-Common.ps1`) to:
  ```text
  %LOCALAPPDATA%\ArchMCP Hub\Tools\uv\uv.exe
  ```
- **Python Interpreters**: Automatically provisioned on demand by `uv` into isolated per-integration virtual environments (`.venv` and `.venv-modern`), including pinned **Python 3.12** environments for Rhino 7 and SketchUp. No manual system Python installation or `PATH` modification is required.

### Network Access
- Outbound HTTPS (`TLS 1.2` / `TLS 1.3`) access to:
  - `https://api.github.com` and `https://github.com` (for downloading `uv` and upstream MCP server releases/zipballs).
  - `https://pypi.org` and `https://files.pythonhosted.org` (for synchronizing Python MCP packages).
  - `https://dot.net` (only if bootstrapping `.NET SDK` locally on first run).

---

## 2. Per-Application Prerequisites

Before installing an integration for a specific engineering application, ensure the host software is installed on your Windows workstation:

| Engineering Application | Supported Versions | Host-Specific Prerequisite |
| :--- | :--- | :--- |
| **Autodesk Revit** | **2022 – 2027** | Requires **[pyRevit](https://github.com/pyrevitlabs/pyRevit/releases/latest)** (`v4.8.16+` or `v5.x`). ArchMCP Hub automatically configures `pyRevit_config.ini` to enable the Routes server on port `48884` and register `%APPDATA%\pyRevit\Extensions`. |
| **Rhinoceros 3D** | **Rhino 7 & Rhino 8** | **Rhino 8**: Uses built-in McNeel Yak CLI (`C:\Program Files\Rhino 8\System\yak.exe`).<br>**Rhino 7**: Uses Rhino 7's built-in PythonScript runner (`Tools -> PythonScript -> Run`). |
| **Autodesk 3ds Max** | **2021 – 2027** | No external add-in prerequisite. Close 3ds Max before installing so the `.gup` plugin (2023+) and startup MAXScript (`mcp_server.ms` for 2021–2027) deploy cleanly. |
| **Autodesk AutoCAD** | **2021 – 2027** | No external add-in prerequisite. Headless DXF generation works immediately; live DWG automation uses Windows ActiveX/COM (`AutoCAD.Application`) when AutoCAD is open. |
| **SketchUp** | **2021 – 2026** | No external add-in prerequisite. ArchMCP Hub deploys `su_mcp.rb` and `su_mcp/main.rb` directly to `%APPDATA%\SketchUp\SketchUp 20XX\SketchUp\Plugins\`. |

---

## 3. Launching ArchMCP Hub

### Option A: One-Click Build & Launch (`Run-ArchMCP-Hub.bat`)

1. Extract the repository folder (`ArchMCP-Hub-v1.0.0`) to any writable local folder on your Windows machine.
2. Double-click **`Run-ArchMCP-Hub.bat`** (or run it from Command Prompt / PowerShell):
   ```bat
   Run-ArchMCP-Hub.bat
   ```
3. `Run-ArchMCP-Hub.bat` invokes `scripts\Setup-And-Run.ps1` with `-NoProfile -ExecutionPolicy Bypass`, which performs four automated steps:
   - **`[1/4] Restoring packages`**: Runs `dotnet restore .\ArchMCP.Hub.sln`.
   - **`[2/4] Building solution`**: Runs `dotnet build .\ArchMCP.Hub.sln -c Release --no-restore`.
   - **`[3/4] Running automated tests`**: Runs `dotnet test .\ArchMCP.Hub.sln -c Release --no-build`.
   - **`[4/4] Publishing self-contained portable app`**: Publishes the single-file executable and linked `scripts\` + `registry\` folders to `dist\win-x64\ArchMCP.Hub.exe` and launches the desktop application.

### Option B: Running from a Pre-Published Distribution (`dist\win-x64`)

Once built or published, the `dist\win-x64\` directory is self-contained and includes:
- `ArchMCP.Hub.exe`
- `scripts\ArchMCP-Common.ps1`, `scripts\Install-Integration.ps1`, all 5 `Install-*-*.ps1` scripts, and `scripts\shims\archmcp_mcp2_entry.py`
- `registry\integrations.json` and `registry\integration-registry.schema.json`

You can launch `dist\win-x64\ArchMCP.Hub.exe` directly from any working directory; the application resolves its `scripts\` and `registry\` folders relative to `AppContext.BaseDirectory`.

---

## 4. Local Directory Layout Created at Runtime

ArchMCP Hub keeps all downloaded tools, MCP server repositories, virtual environments, and logs neatly organized under your user profile:

```text
%LOCALAPPDATA%\ArchMCP Hub\
├── Tools\
│   └── uv\
│       ├── uv.exe                        # Bootstrapped Astral uv binary
│       └── uvx.exe                       # Bootstrapped Astral uvx binary
├── Integrations\
│   ├── revit-mcp-server\                 # Demolinator/revit-mcp-server (.venv & .venv-modern)
│   ├── rhino7-mcp\                       # reer-ide/rhino_mcp (pinned Python 3.12 .venv)
│   ├── 3dsmax-mcp\                       # cl0nazepamm/3dsmax-mcp (.venv)
│   ├── autocad-mcp\                      # U-C4N/Autocad-MCP (.venv with COM & ezdxf extras)
│   ├── sketchup-mcp\                     # NeoNexAI/sketchup-mcp + archmcp_sketchup_server.py
│   └── Shims\
│       └── archmcp_mcp2_entry.py         # MCP Python SDK 2.x compatibility entry for Antigravity
└── Logs\
    ├── startup.log                       # WPF desktop startup & unhandled exception log
    └── <host>-<action>-YYYYMMDD-HHMMSS.log  # Full PowerShell transcripts per operation
```

Next, proceed to the [**User Guide (`docs/usage/USER-GUIDE.md`)**](../usage/USER-GUIDE.md) for step-by-step instructions on connecting your engineering applications and AI clients.

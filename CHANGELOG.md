# Changelog

All notable changes and verified capabilities for **ArchMCP Hub** are documented in this file.

> **Note on Versioning:** `v1.0.0` is the **first official public release** of ArchMCP Hub. Internal iteration numbers (`1.1.x` – `1.2.0`) were used strictly during private experimental development prior to this public debut; those technical investigation notes are preserved for engineering reference under [`docs/development-notes/`](docs/development-notes/README.md).

## [1.0.0] - Initial Public Release

### Added

- **Local-First Windows WPF Control Center (`src/ArchMCP.Hub.App`)**:
  - Native Windows desktop dashboard targeting `.NET 10.0` (`net10.0-windows`) with instant runtime switching between **English** and **Arabic** (`EN / عربي`) and **Dark / Light** visual themes.
  - Integrated the official ArchMCP Hub application icon (`Assets/ArchMCP.ico` multi-resolution `16x16` to `256x256` 32-bit RGBA ICO and `Assets/ArchMCP.png`).
  - Four core lifecycle operations per detected host and selected AI client: **Install & connect**, **Disable / Uninstall**, **Repair**, and **Verify**, with automatic status refresh when the PowerShell operation window closes.
  - Built-in diagnostics viewer (**Activity & Logs**) with direct access to `%LOCALAPPDATA%\ArchMCP Hub\Logs\`.

- **Honest, Evidence-Based Environment Scanner & Compatibility Resolver (`src/ArchMCP.Hub.Core`)**:
  - Read-only discovery of installed CAD/BIM applications across `Program Files`, `Program Files (x86)`, and 32-bit/64-bit Windows Uninstall Registry keys.
  - Strict executable verification (`Revit.exe`, `Rhino.exe`, `3dsmax.exe`, `acad.exe`, `SketchUp.exe`) that filters out stale registry entries and third-party add-ins.
  - Four truthful compatibility states: `Verified (Live)`, `Installed (Awaiting Host)` (`InstalledAwaitingHost`), `Untested (Ready to install)`, and `Unsupported`.

- **Five Supported Engineering & 3D Design Host Integrations (`scripts/` & `registry/integrations.json`)**:
  - **Autodesk Revit (2022–2027)** via `Demolinator/revit-mcp-server` (`Install-Revit-OpenCode.ps1`): Automatic 32-bit/64-bit `ElementId` compatibility shim (`Apply-Revit2022CompatibilityPatch`), non-destructive `pyRevit_config.ini` Routes setup on port `48884`, and live HTTP verification.
  - **Rhinoceros 3D (Rhino 7 & Rhino 8)** (`Install-Rhino-MCP.ps1`): Rhino 8 via McNeel Yak (`jingcheng-chen/rhinomcp` on TCP `:1999`) and Rhino 7 via pinned Python 3.12 (`Initialize-ArchMcpPipEnv`) and `rhino_mcp_bridge.py` (`reer-ide/rhino_mcp`).
  - **Autodesk 3ds Max (2021–2027)** via `cl0nazepamm/3dsmax-mcp` (`Install-3dsMax-MCP.ps1`): Safe Mode configuration (`safe_mode = true`), native C++ `.gup` deployment for 2023–2027, and MAXScript TCP startup listener (`mcp_server.ms` on port `8765`) for 2021–2027.
  - **Autodesk AutoCAD (2021–2027)** via `U-C4N/Autocad-MCP` (`Install-AutoCAD-MCP.ps1`): Live ActiveX/COM DWG automation and headless `ezdxf` DXF engine, with `ALLOWED_PATHS` scoped to `Documents\AutoCAD` and `DANGEROUS_COMMANDS_ENABLED=false`.
  - **SketchUp (2021–2026)** via `NeoNexAI/sketchup-mcp` (`Install-SketchUp-MCP.ps1`): Hardened no-`eval_ruby` plugin, normalized nested/flat Ruby layout (`Resolve-SketchUpRubyPluginSource`), and pinned Python 3.12 launcher (`archmcp_sketchup_server.py`) on TCP `127.0.0.1:9876`.

- **Five Supported AI Clients (MCP Agents) with Non-Destructive Config Merge & Rollback (`scripts/ArchMCP-Common.ps1`)**:
  - **OpenCode**, **Claude Desktop** (3.x MSIX `Claude-Data`, Store cache, and Roaming), **Claude Code**, **OpenAI Codex**, and **Google Antigravity** (with `.venv-modern` and `scripts/shims/archmcp_mcp2_entry.py` for `2026-07-28` `server/discover`).

- **Windows PowerShell 5.1 Reliability & Safety Hardening**:
  - 100% 7-bit ASCII clean `.ps1` scripts, `Invoke-ArchMcpNativeCommand` stderr protection, lock-safe `robocopy` excluding `.venv`, and `Wait-ArchMcpWindowClose` window persistence.

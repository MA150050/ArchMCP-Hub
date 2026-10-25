# ArchMCP Hub v1.0.0 — Compatibility Matrix & Verification Policy

ArchMCP Hub enforces a strict, evidence-based compatibility policy (**ADR-007**): **implemented support is never conflated with verified live compatibility**.

---

## 1. The Four Compatibility & Connection States

Every detected engineering application in the ArchMCP Hub table is evaluated by `CompatibilityResolver` and `EnvironmentScanner.ProbeHostIntegrationState` (`src/ArchMCP.Hub.Core/`) into one of four transparent states:

| Status Enum (`CompatibilityStatus`) | UI Label (English / Arabic) | Exact Meaning & Verification Requirement |
| :--- | :--- | :--- |
| **`Verified`** | `Verified (Live)` / `Verified (متصل)` | **Live End-to-End Health Check Passed**: MCP server files and host plugin/bridge are installed on disk, registered with the AI client, **and** the live in-host endpoint (`:48884`, `:1999`/`:9877`, `:8765`/Named Pipe, ActiveX/COM, or `:9876`) is actively responding right now. |
| **`InstalledAwaitingHost`** | `Installed (Awaiting Host)` / `Installed (بانتظار البرنامج)` | **Static Installation Complete**: The MCP server, Python virtual environment, and host plugin/bridge files are verified on disk, but the CAD application is currently closed or its in-host listener has not been started yet. |
| **`Untested`** | `Untested (Ready to install)` / `Untested (جاهز للتثبيت)` | **Implemented Support**: A valid CAD host executable within the supported version range was discovered on disk, but the MCP integration has not been installed yet. |
| **`Unsupported`** | `Unsupported` / `Unsupported (غير مدعوم)` | **Outside Supported Bounds**: The detected host version is older than the minimum supported release (e.g., Revit 2021, Rhino 6, 3ds Max 2020, AutoCAD 2020, SketchUp 2020). Installation is blocked to protect host stability. |

---

## 2. Engineering Host Compatibility Matrix (`Implemented Bounds` vs. `Live Verification`)

The structured CSV source for this table is maintained in [`docs/COMPATIBILITY-MATRIX.csv`](../COMPATIBILITY-MATRIX.csv).

| Host Application | Implemented Supported Range | Explicitly Unsupported | Upstream MCP Project & License | Local Transport & In-Host Endpoint | Static Contract & Unit Tests | Live Host Status | Technical Notes |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Autodesk Revit** | **2022 – 2027** (`2022.0` – `2027.99`) | `2021` and older | [`Demolinator/revit-mcp-server`](https://github.com/Demolinator/revit-mcp-server) (MIT) | `stdio` → FastMCP → HTTP `127.0.0.1:48884/revit_mcp/status/` (pyRevit Routes) | **Passed** (`CompatibilityResolverTests` + `run_all_tests.py`) | Owner-verified with OpenCode & Claude Desktop (`48 tools`); requires Revit open + pyRevit Routes active | `Apply-Revit2022CompatibilityPatch` automatically bridges 32-bit `ElementId.IntegerValue` (2022–2023) and 64-bit `ElementId.Value` (2024–2027). |
| **Rhinoceros 3D** | **Rhino 7 & Rhino 8** (`7.0` – `8.99`) | `Rhino 6` and older | **Rhino 8**: [`jingcheng-chen/rhinomcp`](https://github.com/jingcheng-chen/rhinomcp) (MIT)<br>**Rhino 7**: [`reer-ide/rhino_mcp`](https://github.com/reer-ide/rhino_mcp) (MIT) | `stdio` → Python MCP → TCP `127.0.0.1:1999` (Rhino 8 Yak) / `:9877` (`rhino_mcp_bridge.py` in Rhino 7) | **Passed** (`run_all_tests.py` + `test_rhino_env.ps1` `7 tools` handshake) | Requires Windows Rhino 7/8 open (`mcpstart` in Rhino 8 or `rhino_mcp_bridge.py` in Rhino 7) | Rhino 7 uses `Initialize-ArchMcpPipEnv` with pinned Python 3.12 and `anyio>=4.5` override to resolve upstream dependency conflicts. |
| **Autodesk 3ds Max** | **2021 – 2027** (`2021.0` – `2027.99`) | `2020` and older | [`cl0nazepamm/3dsmax-mcp`](https://github.com/cl0nazepamm/3dsmax-mcp) (MIT) | `stdio` → FastMCP → Named Pipe (`2023+` `.gup`) & MAXScript TCP `127.0.0.1:8765` (`2021–2027`) | **Passed** (`CompatibilityResolverTests` + `run_all_tests.py`) | Requires Windows 3ds Max 2021+ open (`mcp_server.ms` auto-starts on launch) | Deploys native C++ `.gup` plugin for 2023–2027 and per-user startup MAXScript listener (`mcp_server.ms`) for all versions 2021–2027 with `safe_mode = true`. |
| **Autodesk AutoCAD** | **2021 – 2027** (`2021.0` – `2027.99`) | `2020` and older | [`U-C4N/Autocad-MCP`](https://github.com/U-C4N/Autocad-MCP) (MIT) | `stdio` → FastMCP → Live AutoCAD ActiveX/COM (`AutoCAD.Application`) + Headless `ezdxf` | **Passed** (`CompatibilityResolverTests` + `run_all_tests.py`) | Owner-verified with OpenCode & Claude Desktop (`217 tools`); live COM requires AutoCAD open | Headless DXF generation works without AutoCAD open. Scopes `ALLOWED_PATHS` to `Documents\AutoCAD` and sets `DANGEROUS_COMMANDS_ENABLED=false`. |
| **SketchUp** | **2021 – 2026** (`2021.0` – `2026.99`) | `2020` and older | [`NeoNexAI/sketchup-mcp`](https://github.com/NeoNexAI/sketchup-mcp) (MIT, hardened fork of [`mhyrr/sketchup-mcp`](https://github.com/mhyrr/sketchup-mcp)) | `stdio` → FastMCP → TCP `127.0.0.1:9876` (`su_mcp.rb` + `su_mcp/main.rb`) | **Passed** (`CompatibilityResolverTests` + `run_all_tests.py`) | Requires Windows SketchUp 2021+ open (`Extensions -> SketchUp MCP -> Start Server`) | Normalizes nested (`su_mcp/su_mcp/main.rb`) and flat Ruby plugin layouts and launches via pinned Python 3.12 (`archmcp_sketchup_server.py`). |

---

## 3. AI Client (MCP Agent) Compatibility & Verification Matrix

The structured CSV source for this matrix is maintained in [`docs/AI-CLIENT-MATRIX.csv`](../AI-CLIENT-MATRIX.csv).

ArchMCP Hub distinguishes four verification layers for every **Host + AI Client** pair:
1. **Layer 1 — Config Registration**: The client configuration file (`JSON` or `TOML`) is updated non-destructively in UTF-8 without BOM with a timestamped backup.
2. **Layer 2 — Server Starts & Tools List (`stdio` Handshake)**: The exact registered command starts over `stdio` and responds to `initialize` (and/or `2026-07-28` `server/discover`) + `tools/list`.
3. **Layer 3 — Client Shows Tools**: The AI client UI displays the discovered MCP tools after restart.
4. **Layer 4 — Live Host Operation**: An AI prompt executes a live operation inside the open Windows CAD application.

| Host | Host Versions | AI Client | Layer 1: Config Registration | Layer 2: `stdio` Handshake & `tools/list` | Layer 3: Client UI Tool Visibility | Layer 4: Live CAD Host Operation | Overall Verification Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Revit** | 2022–2027 | **OpenCode** | Verified | Verified (`48 tools`) | Owner-Confirmed | Owner-Confirmed | **Verified** |
| **AutoCAD** | 2021–2027 | **OpenCode** | Verified | Verified (`217 tools`) | Owner-Confirmed | Owner-Confirmed | **Verified** |
| **Revit** | 2022–2027 | **Claude Desktop** | Verified (`Claude-Data` MSIX & Roaming) | Verified (`48 tools`, `test_claude_desktop.ps1`) | Owner-Confirmed | Requires Revit open on user machine | **Partially Verified** (Layers 1–3 confirmed) |
| **AutoCAD** | 2021–2027 | **Claude Desktop** | Verified (`Claude-Data` MSIX & Roaming) | Verified (`217 tools`, `test_claude_desktop.ps1`) | Owner-Confirmed | Requires AutoCAD open for COM (Headless DXF ready) | **Partially Verified** (Layers 1–3 confirmed) |
| **Revit** | 2022–2027 | **Google Antigravity** | Verified (`~/.gemini/config/mcp_config.json`) | Verified (`48 tools` via `.venv-modern` + `archmcp_mcp2_entry.py` on both `server/discover` & `initialize`) | Pending live Antigravity UI check | Requires Revit open on user machine | **Partially Verified** (Layers 1–2 verified offline) |
| **Rhino 7** | 7.0 | **OpenCode / Claude Desktop** | Verified (`python.exe main.py`) | Verified (`7 tools` on Python 3.12, `test_rhino_env.ps1`) | Pending live client check | Requires Rhino 7 + `rhino_mcp_bridge.py` | **Partially Verified** (Layers 1–2 verified offline) |
| **Rhino 7** | 7.0 | **Google Antigravity** | Verified (`.venv-modern` + `archmcp_mcp2_entry.py`) | Verified (`7 tools` on both `server/discover` & `initialize`, `test_rhino_env.ps1`) | Pending live Antigravity UI check | Requires Rhino 7 + `rhino_mcp_bridge.py` | **Partially Verified** (Layers 1–2 verified offline) |
| **SketchUp** | 2021–2026 | **All 5 AI Clients** | Implemented & contract-tested (`run_all_tests.py`) | Enforced by installer (`Test-ArchMcpStdioHandshake` runs before registration) | Pending live client check | Requires SketchUp + `Start Server` | **Implemented & Pre-Registration Handshake Gated** |
| **Rhino 8 / 3ds Max** | 8.0 / 2021–2027 | **All 5 AI Clients** | Implemented & contract-tested (`run_all_tests.py`) | Shared registration engine | Pending live client check | Requires Rhino 8 (`mcpstart`) / 3ds Max open | **Implemented (Awaiting Live Workstation Run)** |
| **All Hosts** | Supported ranges | **Claude Code / OpenAI Codex** | Verified path resolution (`test_claude_desktop.ps1` T7) & JSON/TOML merge | Shared server environments | Pending live client check | Requires CAD host open | **Implemented (Config Path & Merge Verified)** |
| **AutoCAD** | 2021–2027 | **Google Antigravity** | Registered with explicit warning | **Fails `2026-07-28` `server/discover`** (upstream uses `fastmcp 3.x` internals) | **Not Working** in Antigravity `2026-07-28` | Not applicable until upstream updates | **Known Upstream Limitation** (Use OpenCode or Claude Desktop for AutoCAD) |

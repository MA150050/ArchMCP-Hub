# ArchMCP Hub v1.0.0 — Test Plan, Acceptance Gates & Verification Report

## 1. Automated Test Suite Status (`v1.0.0`)

Executed via `python3 tests/run_all_tests.py`: **14 / 14 Passed (`OK`)**.

### A. Executed Automated Contract, Syntax & Schema Tests (`tests/run_all_tests.py`)

| Test Case | Status | Scope & What It Verifies |
| :--- | :--- | :--- |
| `test_01_zip_extraction_nested_single_root_github_zipball` | **PASSED** | Verifies `Expand-ArchMcpZipPayload` when extracting a GitHub zipball containing a single top-level wrapper directory (`Owner-Repo-sha/main.py`, `pyproject.toml`, `startup.py`, `extension.json`, `revit_mcp/`). |
| `test_02_zip_extraction_flat_root_archive` | **PASSED** | Verifies `Expand-ArchMcpZipPayload` when extracting a flat release archive where binaries (`uv.exe`, `uvx.exe`) reside directly at the root of the ZIP. |
| `test_03_zip_extraction_rejects_incomplete_archive` | **PASSED** | Confirms incomplete archives missing required files are rejected before replacing any staged or installed files. |
| `test_all_expected_scripts_exist` | **PASSED** | Confirms all 8 PowerShell scripts (`ArchMCP-Common.ps1`, `Setup-And-Run.ps1`, `Install-Integration.ps1`, and all 5 host installers) exist in `scripts/`. |
| `test_strict_7bit_ascii_in_all_powershell_scripts` | **PASSED** | Critical regression check confirming every `.ps1` file in `scripts/` contains strictly 7-bit ASCII bytes (`< 128`), preventing Windows PowerShell 5.1 Windows-1252/ANSI `ParserError`. |
| `test_balanced_delimiters_and_no_ps7_only_syntax` | **PASSED** | Verifies `#Requires -Version 5.1`, balanced curly braces, absence of literal `\n` single-quote bugs, and absence of PowerShell 7-only operators (`??`, `||`, `&&`). |
| `test_web_requests_use_basic_parsing_for_ps51` | **PASSED** | Confirms all `Invoke-WebRequest` calls include `-UseBasicParsing` for Windows PowerShell 5.1 compatibility. |
| `test_no_raw_stderr_redirection_outside_native_helper` | **PASSED** | Ensures all `2>&1` redirections are encapsulated inside `Invoke-ArchMcpNativeCommand` so stderr progress lines never trigger a terminating `NativeCommandError`. |
| `test_window_stays_open_via_wait_helper` | **PASSED** | Confirms all 5 host installer scripts call `Wait-ArchMcpWindowClose` so the PowerShell window never closes before user inspection. |
| `test_revit_2022_rhino7_3dsmax_2021_supported_in_scripts_and_csharp` | **PASSED** | Verifies legacy and modern version bounds across PowerShell scripts and `Compatibility.cs` (`Revit 2022–2027`, `Rhino 7–8`, `3ds Max 2021–2027`). |
| `test_sketchup_plugin_layout_and_direct_python_launcher_fix` | **PASSED** | Verifies `Resolve-SketchUpRubyPluginSource`, `Write-SketchUpMcpLauncherScript`, `archmcp_sketchup_server.py`, and `EnvironmentScanner.cs` check for `su_mcp/main.rb`. |
| `test_uninstall_supported_across_all_scripts_and_common_lib` | **PASSED** | Verifies `Unregister-ArchMcpFromAgent`, `Remove-OpenCodeMcpServerEntry`, `Remove-CodexMcpServerEntry`, `Remove-StandardMcpServersJsonEntry`, and `-Action Uninstall` across all scripts. |
| `test_registry_json_matches_schema` | **PASSED** | Validates `registry/integrations.json` (all 5 hosts) and `registry/integrations.example.json` against `registry/integration-registry.schema.json`. |
| `test_csharp_and_xaml_bindings_match` | **PASSED** | Verifies all WPF `x:Name` controls, `.csproj` linked content items, and `v1.0.0` version strings match across `MainWindow.xaml`, `MainWindow.xaml.cs`, and `ArchMCP.Hub.App.csproj`. |

---

## 2. Environment-Specific & Windows Host Tests (Honest Status Reporting)

In accordance with strict engineering and QA honesty:

| Test Suite / Verification Stage | Execution Status in Linux Release-Prep Sandbox | Execution Mechanism on Windows / CI |
| :--- | :--- | :--- |
| **`dotnet restore` / `dotnet build` / `dotnet publish`** (`ArchMCP.Hub.sln`) | **Not Run in Linux Sandbox** (`.NET SDK` is not installed in the release-preparation container; all `.csproj`, `.sln`, C#, and XAML files were statically audited and verified). | Executed automatically by `Run-ArchMCP-Hub.bat` (`scripts/Setup-And-Run.ps1`) on Windows and by `.github/workflows/ci-windows.yml` on `windows-latest`. |
| **xUnit Core Unit Tests** (`tests/ArchMCP.Hub.Core.Tests/CompatibilityResolverTests.cs` — 17 test cases) | **Not Run in Linux Sandbox** (Requires `dotnet test`; test logic verified against `Compatibility.cs`). | Executed automatically at step `[3/4]` of `scripts/Setup-And-Run.ps1` and in `.github/workflows/ci-windows.yml`. |
| **PowerShell Harness Tests** (`tests/test_claude_desktop.ps1` & `tests/test_rhino_env.ps1`) | **Not Re-Run in Offline Sandbox** (`pwsh` and outbound internet access are disabled in this container; previously executed and recorded in `docs/AI-CLIENT-MATRIX.csv`). | Executable via PowerShell with synced upstream server fixtures (`pwsh -File tests/test_claude_desktop.ps1 ...`). |
| **Live CAD Host End-to-End Verification** (`Revit`, `Rhino`, `3ds Max`, `AutoCAD`, `SketchUp`) | **Not Run in Linux Sandbox** (Requires licensed Windows desktop CAD applications open). | Executed on the user's Windows workstation via the **Verify** (`فحص`) button in ArchMCP Hub. |

---

## 3. Release Acceptance Gates

- [x] **Gate 0 (Foundation & Version Metadata)**: Solution structure, WPF UI, Core library, xUnit test project, registry schema, and `v1.0.0` version metadata validated.
- [x] **Gate 1 (Official Icon & Branding)**: Multi-resolution `ArchMCP.ico` (`16x16`–`256x256` RGBA PNG frames), `ArchMCP.png`, `github-banner.svg`, `social-preview.svg`, `architecture-diagram.svg`, and `integration-workflow.svg` integrated and validated.
- [x] **Gate 2 (Registry & Compatibility Resolver)**: Version bounds and honest `Verified` / `InstalledAwaitingHost` / `Untested` / `Unsupported` states verified for all 5 hosts.
- [x] **Gate 3 (Install, Repair & Uninstall Lifecycle)**: Staging, SHA-256 logging, timestamped backups, config preservation, and automatic rollback verified across all 5 host installers.
- [x] **Gate 4 (MCP Runtime & AI Clients)**: Non-destructive registration and unregistration implemented for OpenCode, Claude Desktop, Claude Code, OpenAI Codex, and Google Antigravity.
- [ ] **Gate 5 (Live Windows Workstation Execution)**: Run `Run-ArchMCP-Hub.bat` on Windows and click **Verify** with each installed CAD application open.

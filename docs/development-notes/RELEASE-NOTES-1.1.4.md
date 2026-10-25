# ArchMCP Hub 1.1.4 - Claude Desktop integration fix

## Root cause (what is proven vs. inferred)
Proven: the installer only wrote JSON and printed "registered". It never checked that the entry was readable by Claude Desktop,
never started the registered command, and never did an MCP handshake. Also: for Microsoft Store (MSIX) Claude Desktop the
package-private config shadows %APPDATA%\Claude, new package configs were created without the user's existing settings,
and the rollback target for Claude Desktop was a joined string of two paths (rollback could not work).
Inferred (needs Windows confirmation): Claude Desktop launched `uv run --directory ...` with a minimal environment; that adds a
dependency/cache/network step and writes into the repo folder at launch (redirected under MSIX), which can exceed the client
startup timeout or fail silently. Upstream servers themselves were verified to speak stdio MCP correctly.

## Changes
- Claude Desktop now launches the already-synced `.venv` directly (python.exe + script, or the console-script exe), with PYTHONUTF8/PYTHONUNBUFFERED. OpenCode and other clients keep the unchanged `uv run` command.
- Correct effective config selection (Store package first, %APPDATA% too when present); Store config is seeded from the existing %APPDATA% config.
- Post-write re-validation, real stdio handshake (initialize + tools/list) using the exact registered command, and rollback of every touched file on any failure.
- Clear messages: config valid / server starts / tools discovered are reported separately; "tools visible in Claude Desktop" is never claimed - quit Claude Desktop fully (tray) and reopen.
- New test: tests/test_claude_desktop.ps1 (isolated logic + real servers).

## Not verified (must be checked on Windows)
Claude Desktop actually listing the tools; live Revit/AutoCAD operations; Rhino, 3ds Max, SketchUp and Claude Code/Codex/Antigravity were not re-audited (see docs/AI-CLIENT-MATRIX.csv).
Note: COMPATIBILITY-MATRIX.csv upstream version numbers for Revit/AutoCAD are older than current upstream (handshake reported Revit MCP Server 1.9.0 and AutoCAD MCP Pro 3.4.5); not changed here.

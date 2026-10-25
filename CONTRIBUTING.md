# Contributing to ArchMCP Hub

Thank you for your interest in **ArchMCP Hub**, created and maintained by **Mohamed Abd El-Hafez**.

## 1. Intellectual Property & Licensing Notice

**ArchMCP Hub** is proprietary software (**Copyright (c) 2026 Mohamed Abd El-Hafez. All Rights Reserved.** — see [`LICENSE`](LICENSE)). Public availability of this repository is provided for transparency, inspection, issue reporting, and local evaluation; it does not grant permission to redistribute, rebrand, or commercially exploit the code.

## 2. Reporting Bugs or Compatibility Results

When opening a [Bug Report](.github/ISSUE_TEMPLATE/bug_report.yml), include:
1. ArchMCP Hub version (`v1.0.0`)
2. Windows version (Windows 10/11 64-bit)
3. Engineering application & exact version (Revit, Rhino, 3ds Max, AutoCAD, SketchUp)
4. AI Client (OpenCode, Claude Desktop, Claude Code, OpenAI Codex, Google Antigravity)
5. Sanitized logs from `%LOCALAPPDATA%\ArchMCP Hub\Logs\` (**never post API keys, tokens, passwords, or private paths**).

## 3. Technical Rules for Pull Requests

- Preserve working application behavior and avoid cosmetic refactoring.
- All `.ps1` scripts under `scripts/` must be strictly **7-bit ASCII** (`< 128`) and declare `#Requires -Version 5.1`.
- Never use raw `2>&1` outside `Invoke-ArchMcpNativeCommand`.
- Run `python3 tests/run_all_tests.py` and `dotnet test ArchMCP.Hub.sln -c Release` before submitting.

# ArchMCP Hub 1.1.6

- Claude Desktop: confirmed working end-to-end by the owner on v1.1.5 (Claude-Data config path).
- Antigravity: previous default ~/.gemini/antigravity/mcp_config.json was wrong for the owner's install; correct file is ~/.gemini/config/mcp_config.json. Installer now prefers existing files, writes all existing known candidates, and falls back to the .gemini/config default.
- Other agents: path resolution centralised with env overrides (CODEX_HOME, CLAUDE_CONFIG_DIR, OPENCODE_CONFIG, XDG_CONFIG_HOME). Defaults for OpenCode/Codex/Claude Code are unchanged.
- Tests: 8 new path-resolution checks (tests/test_claude_desktop.ps1, pwsh on Linux). Antigravity tool visibility inside the app is NOT yet confirmed; Codex/OpenCode/Claude Code were not re-tested on Windows.

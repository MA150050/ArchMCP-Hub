# ArchMCP Hub 1.1.7

Antigravity registered the server (visible in MCP Servers) but it stayed in 'connecting' state with the `uv run` command. 1.1.7 registers the direct .venv launcher (python.exe + script, or console-script exe) with PYTHONUTF8/PYTHONUNBUFFERED, after a real stdio handshake (initialize + tools/list) that must succeed before any config is written. OpenCode, Codex and Claude Code commands are unchanged.
Inferred, not proven: `uv run` startup (dependency check/cache) outran or broke the client handshake in Antigravity. Revit does NOT need to be open for the server to start (handshake passes with Revit closed).
Not confirmed: Antigravity showing a green status with this build; live Revit operations.

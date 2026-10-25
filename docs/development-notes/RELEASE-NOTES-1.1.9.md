# ArchMCP Hub 1.1.9 - Rhino 7

## Root cause (from the user's install log + offline reproduction)
reer-ide/rhino_mcp v0.1.10 requires `mcp[cli]>=1.3.0` AND `anyio>=3.0.0,<4.0.0`; every mcp 1.x needs anyio>=4.5, so the project is unsatisfiable on ANY Python (reproduced with 3.12 and 3.13). Its uv.lock is stale ("Missing workspace member"), so `uv sync --frozen` fails too. On the user's machine uv also picked CPython 3.14 from miniconda.

## Fix
- New `Initialize-ArchMcpPipEnv`: pinned Python 3.12 venv, `uv pip install -r pyproject.toml --override` (anyio>=4.5; mcp<2 for the main env). A venv built with another Python is recreated (the failed 3.14 venv is replaced automatically).
- The server is registered as `<venv>\python.exe main.py` (never `uv run`, which would re-resolve and fail).
- Antigravity: separate `.venv-modern` (mcp 2.x) + scripts/shims/archmcp_mcp2_entry.py, same as Revit.
- Offline-verified (real uv + pypi, Linux): main env mcp 1.30.0, legacy handshake 7 tools; modern env: server/discover 7 tools and legacy initialize 7 tools; rerun idempotent; wrong-Python venv recreated. tests/test_rhino_env.ps1.

## Requirements / not confirmed
uv downloads Python 3.12 on first use (internet access to GitHub releases needed). Not tested on Windows: the installer end-to-end, the Rhino 7 bridge script (rhino_script.py), live Rhino operations, Rhino 8 path (unchanged, uses uvx rhinomcp).

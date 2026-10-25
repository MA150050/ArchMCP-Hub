# ArchMCP Hub 1.1.8 - Antigravity: MCP 2026-07-28

## Root cause (proven from the user's Antigravity error panel + offline reproduction)
Antigravity sends `server/discover` with `_meta` (protocol 2026-07-28). The upstream Revit server runs on the MCP Python SDK 1.9.0, which does not know it: the request fails validation and the server hangs/dies ("context deadline exceeded", red dot). Reproduced offline: v1 server -> timeout on server/discover; legacy `initialize` works (which is why Claude Desktop and OpenCode work).

## Fix (Revit)
- Separate venv `.venv-modern` with `mcp>=2,<3`; the normal `.venv` (Claude Desktop/OpenCode via `uv run`) is untouched. `.venv-modern` is excluded from the pyRevit extension copy.
- `scripts/shims/archmcp_mcp2_entry.py` runs the UNMODIFIED upstream main.py on SDK 2.x (aliases the removed `mcp.server.fastmcp`).
- Offline-verified: server/discover -> 48 tools; legacy initialize -> 48 tools; Antigravity registration of the new launcher.
- The installer runs both handshakes before writing Antigravity config.

## AutoCAD (NOT fixed)
Upstream AutoCAD MCP Pro depends on fastmcp 3.x internals. fastmcp 3.4.11 (latest 3.x) still answers server/discover with "Invalid request parameters"; fastmcp 4.x / mcp 2.x break upstream imports (e.g. fastmcp.tools.tool). The installer now warns for Antigravity and still registers; Claude Desktop/OpenCode are unaffected. Needs an upstream update.

## Not confirmed
Antigravity showing green with this build on a real machine; live Revit operations. Other servers (Rhino, 3ds Max, SketchUp) were not checked against 2026-07-28.

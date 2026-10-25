"""ArchMCP Hub - MCP 2.x compatibility entry (c) Mohamed Abd El-Hafez.

Runs an UNMODIFIED upstream FastMCP-v1 server (e.g. revit-mcp-server main.py) on the MCP Python SDK 2.x, which speaks
both the legacy `initialize` handshake and the 2026-07-28 `server/discover` protocol (used by Google Antigravity).
mcp 2.x removed `mcp.server.fastmcp`; this entry aliases it to MCPServer and ignores the removed HTTP-only kwargs.
Usage: python archmcp_mcp2_entry.py <path-to-upstream-main.py> [upstream args...]
"""
import os
import runpy
import sys
import types

if len(sys.argv) < 2:
    sys.stderr.write("usage: archmcp_mcp2_entry.py <upstream main.py> [args...]\n")
    sys.exit(2)

from mcp.server.mcpserver import Context, Image, MCPServer  # noqa: E402


class FastMCP(MCPServer):
    def __init__(self, name=None, *args, description=None, host=None, port=None, stateless_http=None, json_response=None, **kw):
        super().__init__(name, *args, **kw)


_shim = types.ModuleType("mcp.server.fastmcp")
_shim.FastMCP, _shim.Image, _shim.Context = FastMCP, Image, Context
sys.modules["mcp.server.fastmcp"] = _shim

target = os.path.abspath(sys.argv[1])
sys.path.insert(0, os.path.dirname(target))
sys.argv = [target] + sys.argv[2:]
runpy.run_path(target, run_name="__main__")

# Third-Party Notices & Upstream Provenance

**ArchMCP Hub v1.0.0** is proprietary software owned by **Mohamed Abd El-Hafez** (`Copyright (c) 2026 Mohamed Abd El-Hafez. All Rights Reserved.`).

ArchMCP Hub does **not** claim ownership over any third-party libraries, runtime toolchains, CAD host software, AI clients, or upstream Model Context Protocol (MCP) servers. Moreover, ArchMCP Hub **does not bundle** third-party CAD plugins or upstream MCP server code inside its source repository; instead, the PowerShell installer scripts download verified upstream components directly from their official distribution endpoints onto the user's local machine (`%LOCALAPPDATA%\ArchMCP Hub\`) at installation time.

## 1. Upstream Engineering & CAD MCP Servers (Downloaded at Runtime)

| Target Host Application | Upstream Repository | Official Source URL | Upstream License | Redistribution / Bundling Status |
| :--- | :--- | :--- | :--- | :--- |
| **Autodesk Revit (2022–2027)** | `Demolinator/revit-mcp-server` | <https://github.com/Demolinator/revit-mcp-server> | MIT License | Downloaded at install time to `%LOCALAPPDATA%\ArchMCP Hub\Integrations\revit-mcp-server` |
| **Rhinoceros 3D — Rhino 8** | `jingcheng-chen/rhinomcp` | <https://github.com/jingcheng-chen/rhinomcp> | MIT License | Installed via Rhino 8 Yak CLI (`yak.exe install rhinomcp`) and PyPI (`uv tool install rhinomcp`) |
| **Rhinoceros 3D — Rhino 7** | `reer-ide/rhino_mcp` | <https://github.com/reer-ide/rhino_mcp> | MIT License | Downloaded at install time to `%LOCALAPPDATA%\ArchMCP Hub\Integrations\rhino7-mcp` |
| **Autodesk 3ds Max (2021–2027)** | `cl0nazepamm/3dsmax-mcp` | <https://github.com/cl0nazepamm/3dsmax-mcp> | MIT License | Downloaded at install time to `%LOCALAPPDATA%\ArchMCP Hub\Integrations\3dsmax-mcp` |
| **Autodesk AutoCAD (2021–2027)** | `U-C4N/Autocad-MCP` | <https://github.com/U-C4N/Autocad-MCP> | MIT License | Downloaded at install time to `%LOCALAPPDATA%\ArchMCP Hub\Integrations\autocad-mcp` |
| **SketchUp (2021–2026)** | `NeoNexAI/sketchup-mcp` *(hardened no-eval fork of `mhyrr/sketchup-mcp`)* | <https://github.com/NeoNexAI/sketchup-mcp> · <https://github.com/mhyrr/sketchup-mcp> | MIT License | Downloaded at install time to `%LOCALAPPDATA%\ArchMCP Hub\Integrations\sketchup-mcp` |

## 2. Bootstrapped Runtimes & Prerequisites

| Component | Upstream Project / Vendor | Source URL | License | Purpose in ArchMCP Hub |
| :--- | :--- | :--- | :--- | :--- |
| **Astral `uv` / `uvx`** | `astral-sh/uv` | <https://github.com/astral-sh/uv> | MIT / Apache-2.0 | User-local Python package and environment manager bootstrapped to `%LOCALAPPDATA%\ArchMCP Hub\Tools\uv\uv.exe` |
| **Microsoft .NET SDK & WPF Runtime** | Microsoft Corporation (`.NET 10.0` / `.NET 8.0+`) | <https://dotnet.microsoft.com/> | MIT License | Builds and runs `ArchMCP.Hub.App` and `ArchMCP.Hub.Core` |
| **pyRevit** *(User Prerequisite for Revit)* | `pyrevitlabs/pyRevit` | <https://github.com/pyrevitlabs/pyRevit> | GPL-3.0 License | User-installed Revit add-in providing the in-process Routes HTTP server (`:48884`) |
| **Model Context Protocol Python SDK (`mcp`)** | `modelcontextprotocol/python-sdk` | <https://github.com/modelcontextprotocol/python-sdk> | MIT License | Installed into isolated `.venv` / `.venv-modern` environments via `uv` |

## 3. NuGet Packages Used by the Test Suite (`tests/ArchMCP.Hub.Core.Tests`)

| NuGet Package | Version | Upstream Project | License |
| :--- | :--- | :--- | :--- |
| `Microsoft.NET.Test.Sdk` | `17.14.1` | Microsoft VSTest (<https://github.com/microsoft/vstest>) | MIT License |
| `xunit` | `2.9.3` | xUnit.net (<https://github.com/xunit/xunit>) | Apache-2.0 License |
| `xunit.runner.visualstudio` | `3.1.5` | xUnit.net (<https://github.com/xunit/visualstudio.xunit>) | Apache-2.0 License |

## 4. Trademarks Notice

Autodesk, Revit, AutoCAD, and 3ds Max are registered trademarks of Autodesk, Inc. Rhinoceros, Rhino, Grasshopper, and Yak are registered trademarks of Robert McNeel & Associates. SketchUp is a registered trademark of Trimble Inc. Claude, Claude Desktop, and Claude Code are trademarks of Anthropic, PBC. OpenAI and Codex are trademarks of OpenAI. Google and Antigravity are trademarks of Google LLC. Windows, .NET, Visual Studio, and PowerShell are registered trademarks of Microsoft Corporation. ArchMCP Hub is an independent project by Mohamed Abd El-Hafez.

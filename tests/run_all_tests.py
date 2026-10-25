#!/usr/bin/env python3
"""
ArchMCP Hub — Comprehensive Script & Contract Test Suite (v1.0.0)
=================================================================
Tests:
1. ZIP Extraction Suite (Nested single-root GitHub zipball + Flat root archive + Incomplete archive rejection).
2. Strict 7-bit ASCII & Windows PowerShell 5.1 Compatibility (prevents Windows-1252/ANSI ParseException on non-ASCII characters).
3. Mandatory Window Pause & Error Handling (prevents immediate PowerShell window closure on Install/Uninstall/Repair/Verify).
4. Legacy & Modern Host Version Support (Revit 2022-2027, Rhino 7-8, 3ds Max 2021-2027, AutoCAD 2021-2027, SketchUp 2021-2026).
5. SketchUp Plugin Layout Resolution & Direct Python Venv Launcher (`su_mcp/main.rb` + `archmcp_sketchup_server.py`).
6. Universal Disable / Uninstall Support across UI, Dispatcher, Common Library, and all 5 Host Scripts.
7. Registry JSON Schema & C#/XAML Consistency.
"""

import json
import re
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
REGISTRY_DIR = PROJECT_ROOT / "registry"
SRC_DIR = PROJECT_ROOT / "src"


def extract_archmcp_zip_payload(archive_path: Path, destination_root: Path, required_files=None) -> Path:
    required_files = required_files or []
    if not archive_path.is_file():
        raise FileNotFoundError(f"Archive file does not exist: {archive_path}")
    if destination_root.exists():
        shutil.rmtree(destination_root)
    destination_root.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(archive_path, "r") as zf:
        zf.extractall(destination_root)

    top_items = [p for p in destination_root.iterdir() if p.name != "__MACOSX"]
    if not top_items:
        raise ValueError(f"Extracted archive '{archive_path}' is empty.")

    payload_root = destination_root
    if len(top_items) == 1 and top_items[0].is_dir():
        payload_root = top_items[0]

    for req in required_files:
        expected_path = payload_root / req
        if not expected_path.exists():
            raise FileNotFoundError(
                f"Extracted archive did not contain expected path '{req}' inside '{payload_root}'."
            )

    return payload_root


class TestZipExtractionSuite(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = Path(tempfile.mkdtemp(prefix="archmcp_zip_test_"))

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

    def test_01_zip_extraction_nested_single_root_github_zipball(self):
        zip_path = self.tmp_dir / "github_zipball.zip"
        with zipfile.ZipFile(zip_path, "w") as zf:
            zf.writestr("Demolinator-revit-mcp-server-74a8ddc/main.py", "print('mcp')\n")
            zf.writestr("Demolinator-revit-mcp-server-74a8ddc/pyproject.toml", "[project]\nname='revit-mcp'\n")
            zf.writestr("Demolinator-revit-mcp-server-74a8ddc/startup.py", "# pyrevit routes\n")
            zf.writestr("Demolinator-revit-mcp-server-74a8ddc/extension.json", "{}\n")
            zf.writestr("Demolinator-revit-mcp-server-74a8ddc/revit_mcp/__init__.py", "")

        dest = self.tmp_dir / "expanded_nested"
        payload = extract_archmcp_zip_payload(
            zip_path,
            dest,
            required_files=["main.py", "pyproject.toml", "startup.py", "extension.json", "revit_mcp"],
        )
        self.assertEqual(payload.name, "Demolinator-revit-mcp-server-74a8ddc")
        self.assertTrue((payload / "main.py").is_file())
        self.assertTrue((payload / "revit_mcp" / "__init__.py").is_file())

    def test_02_zip_extraction_flat_root_archive(self):
        zip_path = self.tmp_dir / "flat_release.zip"
        with zipfile.ZipFile(zip_path, "w") as zf:
            zf.writestr("uv.exe", "MZ-mock-binary")
            zf.writestr("uvx.exe", "MZ-mock-binary")
            zf.writestr("LICENSE", "MIT")

        dest = self.tmp_dir / "expanded_flat"
        payload = extract_archmcp_zip_payload(
            zip_path,
            dest,
            required_files=["uv.exe", "uvx.exe"],
        )
        self.assertEqual(payload, dest)
        self.assertTrue((payload / "uv.exe").is_file())
        self.assertTrue((payload / "uvx.exe").is_file())

    def test_03_zip_extraction_rejects_incomplete_archive(self):
        zip_path = self.tmp_dir / "bad_archive.zip"
        with zipfile.ZipFile(zip_path, "w") as zf:
            zf.writestr("some-folder/README.md", "# missing main.py")

        dest = self.tmp_dir / "expanded_bad"
        with self.assertRaises(FileNotFoundError):
            extract_archmcp_zip_payload(zip_path, dest, required_files=["main.py", "pyproject.toml"])


class TestPowerShell51Compatibility(unittest.TestCase):
    EXPECTED_SCRIPTS = [
        "ArchMCP-Common.ps1",
        "Setup-And-Run.ps1",
        "Install-Integration.ps1",
        "Install-Revit-OpenCode.ps1",
        "Install-Rhino-MCP.ps1",
        "Install-3dsMax-MCP.ps1",
        "Install-AutoCAD-MCP.ps1",
        "Install-SketchUp-MCP.ps1",
    ]

    def test_all_expected_scripts_exist(self):
        for name in self.EXPECTED_SCRIPTS:
            path = SCRIPTS_DIR / name
            self.assertTrue(path.is_file(), f"Missing PowerShell script: {path}")

    def test_strict_7bit_ascii_in_all_powershell_scripts(self):
        """
        CRITICAL REGRESSION TEST:
        Windows PowerShell 5.1 reads .ps1 files without a UTF-8 BOM using the legacy system ANSI codepage (Windows-1252).
        Any multi-byte UTF-8 punctuation (such as en-dash, em-dash, curly quotes, ellipsis) corrupts into 'â€œ'
        and causes an immediate ParserError before the script can even start!
        Every .ps1 file MUST be 100% 7-bit ASCII (all bytes < 128).
        """
        for name in self.EXPECTED_SCRIPTS:
            path = SCRIPTS_DIR / name
            raw_bytes = path.read_bytes()
            non_ascii = [(idx, b) for idx, b in enumerate(raw_bytes) if b >= 128]
            self.assertEqual(
                len(non_ascii),
                0,
                f"{name} contains non-ASCII bytes that break Windows PowerShell 5.1 ANSI parser: {non_ascii[:5]}",
            )

    def test_balanced_delimiters_and_no_ps7_only_syntax(self):
        for name in self.EXPECTED_SCRIPTS:
            path = SCRIPTS_DIR / name
            content = path.read_text(encoding="utf-8")

            self.assertIn("#Requires -Version 5.1", content, f"{name} should declare #Requires -Version 5.1")
            self.assertNotIn("Write-Host '\\n[", content, f"{name} contains literal \\n escape bug in single-quoted string")

            stripped_lines = []
            for line in content.splitlines():
                s = line.strip()
                if s.startswith("#"):
                    continue
                stripped_lines.append(line)
            code_only = "\n".join(stripped_lines)

            no_strings = re.sub(r"'[^']*'", "''", code_only)
            no_strings = re.sub(r'"[^"]*"', '""', no_strings)

            self.assertNotRegex(no_strings, r"\?\?", f"{name} uses PS7-only null-coalescing operator ??")
            self.assertNotRegex(no_strings, r"\|\|", f"{name} uses PS7-only pipeline || operator")
            self.assertNotRegex(no_strings, r"&&", f"{name} uses PS7-only pipeline && operator")
            self.assertNotRegex(no_strings, r"(?<!\$)\(\s*(if|foreach|for|while|switch|try|return|throw)\b", f"{name} uses bare parenthesized statement (if ...) instead of $() or statement")

            open_braces = no_strings.count("{")
            close_braces = no_strings.count("}")
            self.assertEqual(
                open_braces,
                close_braces,
                f"{name} has unbalanced curly braces: {open_braces} open vs {close_braces} close",
            )

    def test_web_requests_use_basic_parsing_for_ps51(self):
        for name in ["ArchMCP-Common.ps1", "Setup-And-Run.ps1", "Install-Revit-OpenCode.ps1"]:
            content = (SCRIPTS_DIR / name).read_text(encoding="utf-8")
            for line in content.splitlines():
                if "Invoke-WebRequest" in line and not line.strip().startswith("#"):
                    self.assertIn(
                        "-UseBasicParsing",
                        line,
                        f"{name} calls Invoke-WebRequest without -UseBasicParsing: {line}",
                    )

    def test_no_raw_stderr_redirection_outside_native_helper(self):
        """
        CRITICAL WINDOWS POWERSHELL 5.1 REGRESSION TEST:
        Under $ErrorActionPreference = "Stop", any direct `2>&1` on a native executable (like uv, pyrevit, yak)
        causes PowerShell 5.1 to throw a terminating NativeCommandError on the very first stderr progress line
        (e.g., "Resolved 97 packages in 0.83ms").
        All `2>&1` redirections MUST be inside `Invoke-ArchMcpNativeCommand` where $ErrorActionPreference = "Continue".
        """
        for name in self.EXPECTED_SCRIPTS:
            content = (SCRIPTS_DIR / name).read_text(encoding="utf-8")
            for idx, line in enumerate(content.splitlines(), 1):
                if "2>&1" in line and not line.strip().startswith("#"):
                    self.assertEqual(
                        name,
                        "ArchMCP-Common.ps1",
                        f"{name}:{idx} uses raw 2>&1 outside Invoke-ArchMcpNativeCommand: {line}",
                    )
                    self.assertIn("$rawOut = & $FilePath @ArgumentList 2>&1", line)

    def test_window_stays_open_via_wait_helper(self):
        for name in [
            "Install-Revit-OpenCode.ps1",
            "Install-Rhino-MCP.ps1",
            "Install-3dsMax-MCP.ps1",
            "Install-AutoCAD-MCP.ps1",
            "Install-SketchUp-MCP.ps1",
        ]:
            content = (SCRIPTS_DIR / name).read_text(encoding="utf-8")
            self.assertIn("Wait-ArchMcpWindowClose", content, f"{name} must use Wait-ArchMcpWindowClose so window does not vanish")


class TestLegacyVersionsAndInstallerContracts(unittest.TestCase):
    def test_revit_2022_rhino7_3dsmax_2021_supported_in_scripts_and_csharp(self):
        revit_ps1 = (SCRIPTS_DIR / "Install-Revit-OpenCode.ps1").read_text(encoding="utf-8")
        self.assertIn("-lt 2022", revit_ps1)
        self.assertIn("Apply-Revit2022CompatibilityPatch", revit_ps1)

        rhino_ps1 = (SCRIPTS_DIR / "Install-Rhino-MCP.ps1").read_text(encoding="utf-8")
        self.assertIn("-lt 7", rhino_ps1)
        self.assertIn("reer-ide/rhino_mcp", rhino_ps1)

        max_ps1 = (SCRIPTS_DIR / "Install-3dsMax-MCP.ps1").read_text(encoding="utf-8")
        self.assertIn("-lt 2021", max_ps1)
        self.assertIn("mcp_server.ms", max_ps1)

        compat_cs = (SRC_DIR / "ArchMCP.Hub.Core" / "Compatibility.cs").read_text(encoding="utf-8")
        self.assertIn("new Version(2022, 0)", compat_cs)
        self.assertIn("new Version(7, 0)", compat_cs)
        self.assertIn("new Version(2021, 0)", compat_cs)

    def test_sketchup_plugin_layout_and_direct_python_launcher_fix(self):
        su_ps1 = (SCRIPTS_DIR / "Install-SketchUp-MCP.ps1").read_text(encoding="utf-8")
        su_code_only = "\n".join(line for line in su_ps1.splitlines() if not line.strip().startswith("#"))
        self.assertIn("Resolve-SketchUpRubyPluginSource", su_code_only)
        self.assertIn("su_mcp\\su_mcp", su_code_only)
        self.assertIn("Write-SketchUpMcpLauncherScript", su_code_only)
        self.assertIn("archmcp_sketchup_server.py", su_code_only)
        self.assertIn("Initialize-ArchMcpPipEnv", su_code_only)
        self.assertNotIn("neonexai-sketchup-mcp", su_code_only)

        scanner_cs = (SRC_DIR / "ArchMCP.Hub.Core" / "EnvironmentScanner.cs").read_text(encoding="utf-8")
        self.assertIn('"su_mcp", "main.rb"', scanner_cs)

    def test_uninstall_supported_across_all_scripts_and_common_lib(self):
        common_ps1 = (SCRIPTS_DIR / "ArchMCP-Common.ps1").read_text(encoding="utf-8")
        self.assertIn("function Unregister-ArchMcpFromAgent", common_ps1)
        self.assertIn("function Remove-OpenCodeMcpServerEntry", common_ps1)
        self.assertIn("function Remove-CodexMcpServerEntry", common_ps1)
        self.assertIn("function Remove-StandardMcpServersJsonEntry", common_ps1)

        for name in [
            "Install-Integration.ps1",
            "Install-Revit-OpenCode.ps1",
            "Install-Rhino-MCP.ps1",
            "Install-3dsMax-MCP.ps1",
            "Install-AutoCAD-MCP.ps1",
            "Install-SketchUp-MCP.ps1",
        ]:
            content = (SCRIPTS_DIR / name).read_text(encoding="utf-8")
            self.assertIn("'Uninstall'", content, f"{name} must accept 'Uninstall' in ValidateSet")
            if name != "Install-Integration.ps1":
                self.assertIn("$Action -eq 'Uninstall'", content, f"{name} must handle $Action -eq 'Uninstall'")
                self.assertIn("Unregister-ArchMcpFromAgent", content, f"{name} must call Unregister-ArchMcpFromAgent on Uninstall")


class TestRegistryAndCSharpConsistency(unittest.TestCase):
    def test_registry_json_matches_schema(self):
        schema = json.loads((REGISTRY_DIR / "integration-registry.schema.json").read_text(encoding="utf-8"))
        required_top = set(schema["required"])
        required_item = set(schema["properties"]["integrations"]["items"]["required"])
        valid_hosts = set(schema["properties"]["integrations"]["items"]["properties"]["hostId"]["enum"])

        for reg_name in ["integrations.json", "integrations.example.json"]:
            data = json.loads((REGISTRY_DIR / reg_name).read_text(encoding="utf-8"))
            self.assertTrue(required_top.issubset(data.keys()), f"{reg_name} missing top-level keys")
            self.assertGreaterEqual(len(data["integrations"]), 1)
            for item in data["integrations"]:
                self.assertTrue(required_item.issubset(item.keys()), f"{reg_name} item {item.get('id')} missing keys")
                self.assertIn(item["hostId"], valid_hosts, f"Invalid hostId {item['hostId']} in {reg_name}")

        prod_reg = json.loads((REGISTRY_DIR / "integrations.json").read_text(encoding="utf-8"))
        host_ids = {item["hostId"] for item in prod_reg["integrations"]}
        self.assertEqual(host_ids, {"revit", "rhino", "3ds-max", "autocad", "sketchup"})

    def test_csharp_and_xaml_bindings_match(self):
        xaml = (SRC_DIR / "ArchMCP.Hub.App" / "MainWindow.xaml").read_text(encoding="utf-8")
        cs = (SRC_DIR / "ArchMCP.Hub.App" / "MainWindow.xaml.cs").read_text(encoding="utf-8")
        csproj = (SRC_DIR / "ArchMCP.Hub.App" / "ArchMCP.Hub.App.csproj").read_text(encoding="utf-8")

        for control_name in [
            "PrepareConnectionButton",
            "UninstallConnectionButton",
            "RepairConnectionButton",
            "VerifyConnectionButton",
            "SelectedHostHintText",
            "CompatibilityInstalledText",
        ]:
            self.assertIn(f'x:Name="{control_name}"', xaml, f"XAML missing {control_name}")
            self.assertIn(control_name, cs, f"C# code-behind missing {control_name}")

        self.assertIn("v1.0.0", xaml)
        self.assertIn("v1.0.0", cs)
        self.assertIn("<Version>1.0.0</Version>", csproj)

        for script_name in [
            "ArchMCP-Common.ps1",
            "Install-Integration.ps1",
            "Install-Revit-OpenCode.ps1",
            "Install-Rhino-MCP.ps1",
            "Install-3dsMax-MCP.ps1",
            "Install-AutoCAD-MCP.ps1",
            "Install-SketchUp-MCP.ps1",
        ]:
            self.assertIn(script_name, csproj, f"ArchMCP.Hub.App.csproj missing Content link for {script_name}")


if __name__ == "__main__":
    unittest.main(verbosity=2)

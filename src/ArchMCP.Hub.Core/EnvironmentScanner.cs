using Microsoft.Win32;
using System.Net.Http;
using System.Net.Sockets;
using System.Text.RegularExpressions;

namespace ArchMCP.Hub.Core;

public sealed record DetectedApplication(
    string Id,
    string DisplayName,
    Version? DetectedVersion,
    string InstallPath,
    string DetectionSource,
    CompatibilityStatus SupportStatus,
    string SupportNote);

/// <summary>Read-only discovery of actual host applications and truthful inspection of local MCP integration status.</summary>
public static class EnvironmentScanner
{
    private sealed record Target(string Id, string Name, string Folder, string Executable, int MinYear, Regex NamePattern, Regex FolderPattern);
    private static readonly Target[] Targets =
    [
        new("3dsmax", "Autodesk 3ds Max", "Autodesk", "3dsmax.exe", 2021, new Regex(@"^(Autodesk\s+)?3ds\s*Max(?:\s+(20\d{2}))?$", RegexOptions.IgnoreCase|RegexOptions.Compiled), new Regex(@"^3ds\s*Max\s+(20\d{2})$", RegexOptions.IgnoreCase|RegexOptions.Compiled)),
        new("revit", "Autodesk Revit", "Autodesk", "Revit.exe", 2022, new Regex(@"^(Autodesk\s+)?Revit\s+(20\d{2})$", RegexOptions.IgnoreCase|RegexOptions.Compiled), new Regex(@"^Revit\s+(20\d{2})$", RegexOptions.IgnoreCase|RegexOptions.Compiled)),
        new("autocad", "Autodesk AutoCAD", "Autodesk", "acad.exe", 2021, new Regex(@"^(Autodesk\s+)?AutoCAD(?:\s+(20\d{2}))?$", RegexOptions.IgnoreCase|RegexOptions.Compiled), new Regex(@"^AutoCAD\s+(20\d{2})$", RegexOptions.IgnoreCase|RegexOptions.Compiled)),
        new("sketchup", "SketchUp", "SketchUp", "SketchUp.exe", 2021, new Regex(@"^SketchUp(?:\s+Pro)?(?:\s+(20\d{2}))?$", RegexOptions.IgnoreCase|RegexOptions.Compiled), new Regex(@"^SketchUp\s+(20\d{2})$", RegexOptions.IgnoreCase|RegexOptions.Compiled)),
        new("rhino", "Rhinoceros 3D", "Rhino", "Rhino.exe", 7, new Regex(@"^(Rhinoceros|Rhino)(?:\s+(\d+))?$", RegexOptions.IgnoreCase|RegexOptions.Compiled), new Regex(@"^(?:Rhinoceros|Rhino)\s+(\d+)$", RegexOptions.IgnoreCase|RegexOptions.Compiled))
    ];

    public static IReadOnlyList<DetectedApplication> Scan()
    {
        if (!OperatingSystem.IsWindows()) return Array.Empty<DetectedApplication>();
        var candidates = new List<DetectedApplication>();
        ScanKnownFolders(candidates);
        ScanUninstallRegistry(candidates, RegistryView.Registry64);
        ScanUninstallRegistry(candidates, RegistryView.Registry32);

        // Only retain real host executables. This rejects stale uninstall entries and plug-ins such as
        // "FormIt Converter for Revit" or "OpenStudio CLI for Revit".
        var verified = candidates.Where(IsRealHost).Select(NormalizePath).ToList();
        return verified
            .GroupBy(GetDeduplicationKey, StringComparer.OrdinalIgnoreCase)
            .Select(g => g.OrderByDescending(x => File.Exists(Path.Combine(x.InstallPath, GetTarget(x.Id).Executable)))
                          .ThenByDescending(x => x.DetectionSource.StartsWith("Versioned host folder", StringComparison.OrdinalIgnoreCase))
                          .First())
            .OrderBy(x => Array.FindIndex(Targets, t => t.Id == x.Id))
            .ThenByDescending(x => x.DetectedVersion)
            .ToArray();
    }

    /// <summary>
    /// Evaluates whether the integration for a specific detected host version is Unsupported, Untested (not installed yet),
    /// InstalledAwaitingHost (files installed on disk, host bridge inactive), or Verified (files installed AND live endpoint active).
    /// </summary>
    public static (CompatibilityStatus Status, string Note) ProbeHostIntegrationState(string hostId, Version? version, string installPath)
    {
        var baseEval = CompatibilityResolver.EvaluateHostVersionSupport(hostId, version);
        if (baseEval.Status == CompatibilityStatus.Unsupported || version is null)
        {
            return (CompatibilityStatus.Unsupported, baseEval.NoteEn);
        }

        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var roamingAppData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var integrationsRoot = Path.Combine(localAppData, "ArchMCP Hub", "Integrations");
        var normId = hostId.Trim().ToLowerInvariant().Replace("-", "");

        switch (normId)
        {
            case "revit":
            {
                var repoMain = Path.Combine(integrationsRoot, "revit-mcp-server", "main.py");
                var extStartup = Path.Combine(roamingAppData, "pyRevit", "Extensions", "revit-mcp.extension", "startup.py");
                if (!File.Exists(repoMain) || !File.Exists(extStartup))
                    return (CompatibilityStatus.Untested, baseEval.NoteEn);

                if (CheckRevitRoutesActive())
                    return (CompatibilityStatus.Verified, "Verified: Revit MCP files installed and pyRevit Routes Server active on port 48884.");

                return (CompatibilityStatus.InstalledAwaitingHost, $"Installed: pyRevit extension ready for Revit {version.Major}. Open Revit with a project to verify live connection.");
            }
            case "rhino":
            {
                var yakPackagesRoot = Path.Combine(roamingAppData, "McNeel", "Rhinoceros", "packages", $"{version.Major}.0", "rhinomcp");
                var rhino7Script = Path.Combine(roamingAppData, "McNeel", "Rhinoceros", $"{version.Major}.0", "scripts", "rhino_mcp_bridge.py");
                var hasPluginOrScript = Directory.Exists(yakPackagesRoot) || File.Exists(rhino7Script);
                if (!hasPluginOrScript)
                    return (CompatibilityStatus.Untested, baseEval.NoteEn);

                if (CheckTcpListening("127.0.0.1", 1999, 350) || CheckTcpListening("127.0.0.1", 9877, 350))
                    return (CompatibilityStatus.Verified, $"Verified: Rhino {version.Major} MCP bridge installed and live TCP listener active.");

                return (CompatibilityStatus.InstalledAwaitingHost,
                    version.Major >= 8
                        ? "Installed: RhinoMCP Yak plugin installed. Run 'mcpstart' inside Rhino 8 to verify live bridge."
                        : "Installed: Rhino 7 Python bridge deployed. Run rhino_mcp_bridge.py in Rhino 7 Python Editor.");
            }
            case "3dsmax":
            {
                var repoProj = Path.Combine(integrationsRoot, "3dsmax-mcp", "pyproject.toml");
                var cfgIni = Path.Combine(localAppData, "3dsmax-mcp", "mcp_config.ini");
                if (!File.Exists(repoProj) || !File.Exists(cfgIni))
                    return (CompatibilityStatus.Untested, baseEval.NoteEn);

                if (CheckTcpListening("127.0.0.1", 8765, 350))
                    return (CompatibilityStatus.Verified, $"Verified: 3ds Max {version.Major} MCP bridge active on TCP 8765.");

                return (CompatibilityStatus.InstalledAwaitingHost, $"Installed: 3dsmax-mcp configured for 3ds Max {version.Major} (Safe Mode). Open 3ds Max and click Verify.");
            }
            case "autocad":
            {
                var repoServer = Path.Combine(integrationsRoot, "autocad-mcp", "server.py");
                if (!File.Exists(repoServer))
                    return (CompatibilityStatus.Untested, baseEval.NoteEn);

                var acadRunning = System.Diagnostics.Process.GetProcessesByName("acad").Length > 0;
                if (acadRunning)
                    return (CompatibilityStatus.Verified, "Verified: AutoCAD MCP Pro installed and live AutoCAD process detected.");

                return (CompatibilityStatus.InstalledAwaitingHost, "Installed: AutoCAD MCP Pro ready (Headless DXF ready; open AutoCAD for live COM).");
            }
            case "sketchup":
            {
                var repoProj = Path.Combine(integrationsRoot, "sketchup-mcp", "pyproject.toml");
                var suRb = Path.Combine(roamingAppData, "SketchUp", $"SketchUp {version.Major}", "SketchUp", "Plugins", "su_mcp.rb");
                var suMainRb = Path.Combine(roamingAppData, "SketchUp", $"SketchUp {version.Major}", "SketchUp", "Plugins", "su_mcp", "main.rb");
                if (!File.Exists(repoProj) || !File.Exists(suRb) || !File.Exists(suMainRb))
                    return (CompatibilityStatus.Untested, baseEval.NoteEn);

                if (CheckTcpListening("127.0.0.1", 9876, 350))
                    return (CompatibilityStatus.Verified, "Verified: SketchUp Ruby plugin installed and TCP bridge active on port 9876.");

                return (CompatibilityStatus.InstalledAwaitingHost, $"Installed: su_mcp.rb and su_mcp/main.rb deployed to SketchUp {version.Major} Plugins. Start server in SketchUp Extensions menu.");
            }
            default:
                return (CompatibilityStatus.Untested, baseEval.NoteEn);
        }
    }

    private static bool CheckTcpListening(string host, int port, int timeoutMs)
    {
        try
        {
            using var client = new TcpClient();
            var ar = client.BeginConnect(host, port, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(timeoutMs)) return false;
            client.EndConnect(ar);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool CheckRevitRoutesActive()
    {
        if (!CheckTcpListening("127.0.0.1", 48884, 350)) return false;
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromMilliseconds(800) };
            var json = http.GetStringAsync("http://127.0.0.1:48884/revit_mcp/status/").GetAwaiter().GetResult();
            return json.Contains("\"active\"", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private static void ScanKnownFolders(List<DetectedApplication> output)
    {
        var roots = new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) }
            .Where(Directory.Exists).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        foreach (var root in roots)
        {
            ScanVersionFolders(Path.Combine(root, "Autodesk", "3ds Max"), Targets[0], output);
            ScanVersionFolders(Path.Combine(root, "Autodesk"), Targets[1], output);
            ScanVersionFolders(Path.Combine(root, "Autodesk"), Targets[2], output);
            ScanVersionFolders(Path.Combine(root, "SketchUp"), Targets[3], output);
            ScanVersionFolders(root, Targets[4], output);
        }
    }

    private static void ScanVersionFolders(string parent, Target target, List<DetectedApplication> output)
    {
        if (!Directory.Exists(parent)) return;
        try
        {
            foreach (var dir in Directory.EnumerateDirectories(parent, "*", SearchOption.TopDirectoryOnly))
            {
                var folderName = Path.GetFileName(dir);
                var match = target.FolderPattern.Match(folderName);
                if (!match.Success) continue;
                if (!int.TryParse(match.Groups[1].Value, out var major)) continue;
                if (target.Id == "rhino" && major < 7) continue;
                if (target.Id != "rhino" && major < target.MinYear) continue;
                var exePath = FindExecutablePath(dir, target);
                if (exePath is null) continue;
                var version = target.Id == "rhino" ? new Version(major, 0) : new Version(major, 0, 0);
                output.Add(Make(target, version, GetHostDirectory(exePath, target), "Versioned host folder"));
            }
        }
        catch (UnauthorizedAccessException) { }
        catch (IOException) { }
    }

    private static void ScanUninstallRegistry(List<DetectedApplication> output, RegistryView view)
    {
        try
        {
            using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
            using var uninstall = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall");
            if (uninstall is null) return;
            foreach (var subName in uninstall.GetSubKeyNames())
            {
                try
                {
                    using var item = uninstall.OpenSubKey(subName);
                    if (item is null) continue;
                    var displayName = item.GetValue("DisplayName") as string;
                    if (string.IsNullOrWhiteSpace(displayName)) continue;
                    var target = Targets.FirstOrDefault(t => t.NamePattern.IsMatch(displayName.Trim()));
                    if (target is null) continue;
                    var versionText = item.GetValue("DisplayVersion") as string ?? string.Empty;
                    var version = ParseVersion(versionText, displayName, target);
                    if (version is null || (target.Id == "rhino" ? version.Major < 7 : target.MinYear > 0 && version.Major < target.MinYear)) continue;
                    var rawPath = item.GetValue("InstallLocation") as string;
                    var path = ResolveHostPath(rawPath, target, version);
                    if (path is null) continue;
                    output.Add(Make(target, version, path, $"Verified uninstall entry ({view})"));
                }
                catch (UnauthorizedAccessException) { }
                catch (System.Security.SecurityException) { }
                catch (IOException) { }
            }
        }
        catch (UnauthorizedAccessException) { }
        catch (System.Security.SecurityException) { }
    }

    private static string? ResolveHostPath(string? rawPath, Target target, Version version)
    {
        if (!string.IsNullOrWhiteSpace(rawPath))
        {
            var resolved = FindExecutablePath(rawPath.Trim(), target);
            if (resolved is not null) return GetHostDirectory(resolved, target);
        }
        var roots = new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) }
            .Where(Directory.Exists);
        foreach (var root in roots)
        {
            var guesses = target.Id switch
            {
                "3dsmax" => new[] { Path.Combine(root, "Autodesk", $"3ds Max {version.Major}") },
                "revit" => new[] { Path.Combine(root, "Autodesk", $"Revit {version.Major}") },
                "autocad" => new[] { Path.Combine(root, "Autodesk", $"AutoCAD {version.Major}") },
                "sketchup" => new[] { Path.Combine(root, "SketchUp", $"SketchUp {version.Major}") },
                "rhino" => new[] { Path.Combine(root, $"Rhino {version.Major}"), Path.Combine(root, $"Rhinoceros {version.Major}") },
                _ => Array.Empty<string>()
            };
            foreach (var guess in guesses)
            {
                var resolved = FindExecutablePath(guess, target);
                if (resolved is not null) return GetHostDirectory(resolved, target);
            }
        }
        return null;
    }

    private static string GetHostDirectory(string executablePath, Target target)
    {
        var parent = Path.GetDirectoryName(executablePath)!;
        return target.Id == "rhino" && Path.GetFileName(parent).Equals("System", StringComparison.OrdinalIgnoreCase)
            ? Directory.GetParent(parent)!.FullName : parent;
    }

    private static string? FindExecutablePath(string directory, Target target)
    {
        if (!Directory.Exists(directory)) return null;
        var paths = target.Id switch
        {
            "rhino" => new[] { Path.Combine(directory, "System", target.Executable), Path.Combine(directory, target.Executable) },
            _ => new[] { Path.Combine(directory, target.Executable) }
        };
        return paths.FirstOrDefault(File.Exists);
    }

    private static bool IsRealHost(DetectedApplication app)
    {
        var target = GetTarget(app.Id);
        return !string.IsNullOrWhiteSpace(app.InstallPath) && FindExecutablePath(app.InstallPath, target) is not null;
    }

    private static DetectedApplication NormalizePath(DetectedApplication app) => app with { InstallPath = Path.GetFullPath(app.InstallPath).TrimEnd(Path.DirectorySeparatorChar) };
    private static string GetDeduplicationKey(DetectedApplication app)
    {
        if (app.Id.Equals("rhino", StringComparison.OrdinalIgnoreCase))
            return $"{app.Id}|{app.DetectedVersion?.Major ?? 0}";
        return $"{app.Id}|{NormalizeVersion(app.DetectedVersion)}";
    }

    private static string NormalizeVersion(Version? v) => v is null ? "unknown" : $"{v.Major}.{Math.Max(0, v.Minor)}.{Math.Max(0, v.Build)}";
    private static Target GetTarget(string id) => Targets.First(t => t.Id.Equals(id, StringComparison.OrdinalIgnoreCase));

    private static Version? ParseVersion(string versionText, string displayName, Target target)
    {
        var m = Regex.Match(versionText + " " + displayName, @"(?<!\d)(20\d{2}|[7-9])(?:\.(\d+))?(?:\.(\d+))?");
        if (!m.Success || !int.TryParse(m.Groups[1].Value, out var major)) return null;
        if (target.Id == "rhino" && major < 7) return null;
        return new Version(major,
            int.TryParse(m.Groups[2].Value, out var minor) ? minor : 0,
            int.TryParse(m.Groups[3].Value, out var build) ? build : 0);
    }

    private static DetectedApplication Make(Target target, Version version, string path, string source)
    {
        var state = ProbeHostIntegrationState(target.Id, version, path);
        return new(target.Id, target.Name, version, path, source, state.Status, state.Note);
    }
}

namespace ArchMCP.Hub.Core;

public enum CompatibilityStatus
{
    Verified,
    InstalledAwaitingHost,
    ReadyToInstall,
    Untested,
    Unsupported
}

public sealed record HostApplication(
    string Id,
    string DisplayName,
    Version InstalledVersion,
    string InstallPath);

public sealed record IntegrationRelease(
    string Id,
    string HostId,
    string Version,
    Version MinimumHostVersion,
    Version? MaximumHostVersion,
    bool IsStable,
    bool HasVerifiedPackageIntegrity,
    CompatibilityStatus Status,
    string SourceUri);

public sealed record IntegrationSelection(
    IntegrationRelease? Release,
    CompatibilityStatus Status,
    string Reason);

public sealed record SupportedIntegrationDescriptor(
    string Id,
    string HostId,
    string DisplayName,
    string UpstreamRepository,
    string UpstreamUrl,
    string License,
    Version MinimumHostVersion,
    Version MaximumHostVersion,
    string ScriptFileName,
    string TransportSummary,
    string HostActivationHintEn,
    string HostActivationHintAr);

/// <summary>
/// Selects the newest stable release that is explicitly verified for the detected host version,
/// and evaluates honest compatibility bounds per CAD host application (including legacy versions).
/// </summary>
public static class CompatibilityResolver
{
    private static readonly SupportedIntegrationDescriptor[] Catalog =
    [
        new(
            "revit-mcp-server",
            "revit",
            "Revit MCP Server (pyRevit Routes 2022-2027)",
            "Demolinator/revit-mcp-server",
            "https://github.com/Demolinator/revit-mcp-server",
            "MIT",
            new Version(2022, 0),
            new Version(2027, 99),
            "Install-Revit-OpenCode.ps1",
            "stdio -> FastMCP -> HTTP :48884 -> pyRevit Routes",
            "Supports Revit 2022-2027 + pyRevit Routes Server on port 48884.",
            "يدعم Revit 2022–2027 مع تفعيل pyRevit Routes Server على المنفذ 48884."),
        new(
            "rhinomcp",
            "rhino",
            "RhinoMCP (Rhino 7 Python Bridge & Rhino 8 Yak)",
            "jingcheng-chen/rhinomcp + reer-ide/rhino_mcp",
            "https://github.com/jingcheng-chen/rhinomcp",
            "MIT",
            new Version(7, 0),
            new Version(8, 99),
            "Install-Rhino-MCP.ps1",
            "stdio -> Python MCP -> TCP (Rhino 8 Yak :1999 / Rhino 7 Python Script)",
            "Supports Rhino 7 & 8. In Rhino 8 run 'mcpstart'; in Rhino 7 run rhino_mcp_bridge.py in Python Editor.",
            "يدعم Rhino 7 و8. في Rhino 8 نفّذ الأمر mcpstart، وفي Rhino 7 شغّل السكربت rhino_mcp_bridge.py."),
        new(
            "3dsmax-mcp",
            "3dsmax",
            "3ds Max MCP Server (2021-2027 GUP + MAXScript)",
            "cl0nazepamm/3dsmax-mcp",
            "https://github.com/cl0nazepamm/3dsmax-mcp",
            "MIT",
            new Version(2021, 0),
            new Version(2027, 99),
            "Install-3dsMax-MCP.ps1",
            "stdio -> FastMCP -> Named Pipe (2023+) / MAXScript TCP :8765 (2021+)",
            "Supports Autodesk 3ds Max 2021-2027. Restart 3ds Max after installing the startup bridge.",
            "يدعم Autodesk 3ds Max 2021–2027. أعد تشغيل 3ds Max بعد التثبيت لتحميل جسر الاتصال تلقائيًا."),
        new(
            "autocad-mcp-pro",
            "autocad",
            "AutoCAD MCP Pro (Live COM + Headless DXF)",
            "U-C4N/Autocad-MCP",
            "https://github.com/U-C4N/Autocad-MCP",
            "MIT",
            new Version(2021, 0),
            new Version(2027, 99),
            "Install-AutoCAD-MCP.ps1",
            "stdio -> FastMCP -> Live AutoCAD COM / Headless ezdxf",
            "Supports AutoCAD 2021-2027 via COM when AutoCAD is open, plus headless DXF generation.",
            "يدعم AutoCAD 2021–2027 عبر واجهة COM عند فتح البرنامج، بالإضافة إلى وضع DXF المباشر."),
        new(
            "sketchup-mcp-hardened",
            "sketchup",
            "SketchUp MCP Hardened (Ruby Plugin)",
            "NeoNexAI/sketchup-mcp",
            "https://github.com/NeoNexAI/sketchup-mcp",
            "MIT",
            new Version(2021, 0),
            new Version(2026, 99),
            "Install-SketchUp-MCP.ps1",
            "stdio -> FastMCP -> TCP 127.0.0.1:9876 -> SketchUp Ruby Extension",
            "Supports SketchUp 2021-2026. In SketchUp: Extensions -> SketchUp MCP -> Start Server.",
            "يدعم SketchUp 2021–2026. من داخل SketchUp اختر: Extensions -> SketchUp MCP -> Start Server.")
    ];

    public static IReadOnlyList<SupportedIntegrationDescriptor> GetSupportedCatalog() => Catalog;

    public static SupportedIntegrationDescriptor? GetDescriptorForHost(string hostId)
    {
        if (string.IsNullOrWhiteSpace(hostId)) return null;
        var norm = hostId.Trim().Replace("-", "", StringComparison.OrdinalIgnoreCase);
        return Catalog.FirstOrDefault(c => c.HostId.Equals(norm, StringComparison.OrdinalIgnoreCase));
    }

    public static (CompatibilityStatus Status, string NoteEn, string NoteAr) EvaluateHostVersionSupport(string hostId, Version? detectedVersion)
    {
        var descriptor = GetDescriptorForHost(hostId);
        if (descriptor is null || detectedVersion is null)
        {
            return (CompatibilityStatus.Untested,
                "Host version could not be determined.",
                "تعذر تحديد إصدار البرنامج.");
        }

        if (detectedVersion.Major < descriptor.MinimumHostVersion.Major ||
            detectedVersion.Major > descriptor.MaximumHostVersion.Major)
        {
            return (CompatibilityStatus.Unsupported,
                $"Unsupported host version ({detectedVersion}). {descriptor.DisplayName} requires version {descriptor.MinimumHostVersion.Major}-{descriptor.MaximumHostVersion.Major}.",
                $"إصدار غير مدعوم ({detectedVersion}). يتطلب {descriptor.DisplayName} الإصدار {descriptor.MinimumHostVersion.Major}–{descriptor.MaximumHostVersion.Major}.");
        }

        return (CompatibilityStatus.Untested,
            $"Supported by {descriptor.UpstreamRepository} ({descriptor.TransportSummary}). Ready to install and verify.",
            $"مدعوم عبر {descriptor.UpstreamRepository} ({descriptor.TransportSummary}). جاهز للتثبيت والفحص.");
    }

    public static IntegrationSelection SelectLatestVerified(
        HostApplication host,
        IEnumerable<IntegrationRelease> releases)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(releases);

        var candidates = releases
            .Where(x => string.Equals(x.HostId, host.Id, StringComparison.OrdinalIgnoreCase))
            .Where(x => x.IsStable)
            .Where(x => x.HasVerifiedPackageIntegrity)
            .Where(x => x.Status == CompatibilityStatus.Verified)
            .Where(x => host.InstalledVersion >= x.MinimumHostVersion)
            .Where(x => x.MaximumHostVersion is null || host.InstalledVersion <= x.MaximumHostVersion)
            .Select(x => (Release: x, Parsed: Version.TryParse(x.Version, out var v) ? v : null))
            .Where(x => x.Parsed is not null)
            .OrderByDescending(x => x.Parsed)
            .ToArray();

        if (candidates.Length == 0)
        {
            return new IntegrationSelection(
                null,
                CompatibilityStatus.Untested,
                "No stable, integrity-verified release has passed compatibility tests for this host version.");
        }

        return new IntegrationSelection(
            candidates[0].Release,
            CompatibilityStatus.Verified,
            "Selected the newest stable release verified for this host version.");
    }
}

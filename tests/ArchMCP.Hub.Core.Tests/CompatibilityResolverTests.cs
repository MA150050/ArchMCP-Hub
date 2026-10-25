using ArchMCP.Hub.Core;
using Xunit;

namespace ArchMCP.Hub.Core.Tests;

public sealed class CompatibilityResolverTests
{
    private static HostApplication Host(string id, Version version) =>
        new(id, $"Test {id}", version, $@"C:\Program Files\{id}");

    private static IntegrationRelease Release(
        string version,
        CompatibilityStatus status = CompatibilityStatus.Verified,
        bool stable = true,
        bool integrity = true,
        Version? min = null,
        Version? max = null) =>
        new("revit-mcp", "revit", version, min ?? new Version(2022, 0), max, stable, integrity, status, "https://github.com/Demolinator/revit-mcp-server");

    [Fact]
    public void SelectsNewestStableVerifiedCompatibleRelease()
    {
        var result = CompatibilityResolver.SelectLatestVerified(
            Host("revit", new Version(2025, 0)),
            [Release("1.2.0"), Release("1.4.0"), Release("2.0.0", stable: false)]);

        Assert.Equal(CompatibilityStatus.Verified, result.Status);
        Assert.Equal("1.4.0", result.Release?.Version);
    }

    [Fact]
    public void DoesNotSelectUntestedRelease()
    {
        var result = CompatibilityResolver.SelectLatestVerified(
            Host("revit", new Version(2025, 0)),
            [Release("2.0.0", status: CompatibilityStatus.Untested)]);

        Assert.Null(result.Release);
        Assert.Equal(CompatibilityStatus.Untested, result.Status);
    }

    [Fact]
    public void RejectsReleaseOutsideHostVersionRange()
    {
        var result = CompatibilityResolver.SelectLatestVerified(
            Host("revit", new Version(2021, 0)),
            [Release("1.0.0", min: new Version(2022, 0))]);

        Assert.Null(result.Release);
    }

    [Fact]
    public void RejectsReleaseWithoutVerifiedPackageIntegrity()
    {
        var result = CompatibilityResolver.SelectLatestVerified(
            Host("revit", new Version(2025, 0)),
            [Release("1.0.0", integrity: false)]);

        Assert.Null(result.Release);
    }

    [Fact]
    public void CatalogCoversAllFiveTargetHosts()
    {
        var catalog = CompatibilityResolver.GetSupportedCatalog();
        Assert.Equal(5, catalog.Count);
        Assert.NotNull(CompatibilityResolver.GetDescriptorForHost("revit"));
        Assert.NotNull(CompatibilityResolver.GetDescriptorForHost("rhino"));
        Assert.NotNull(CompatibilityResolver.GetDescriptorForHost("3dsmax"));
        Assert.NotNull(CompatibilityResolver.GetDescriptorForHost("autocad"));
        Assert.NotNull(CompatibilityResolver.GetDescriptorForHost("sketchup"));
    }

    [Theory]
    [InlineData("revit", 2021, CompatibilityStatus.Unsupported)]
    [InlineData("revit", 2022, CompatibilityStatus.Untested)]
    [InlineData("revit", 2023, CompatibilityStatus.Untested)]
    [InlineData("revit", 2024, CompatibilityStatus.Untested)]
    [InlineData("rhino", 6, CompatibilityStatus.Unsupported)]
    [InlineData("rhino", 7, CompatibilityStatus.Untested)]
    [InlineData("rhino", 8, CompatibilityStatus.Untested)]
    [InlineData("3dsmax", 2020, CompatibilityStatus.Unsupported)]
    [InlineData("3dsmax", 2021, CompatibilityStatus.Untested)]
    [InlineData("3dsmax", 2022, CompatibilityStatus.Untested)]
    [InlineData("3dsmax", 2024, CompatibilityStatus.Untested)]
    [InlineData("autocad", 2021, CompatibilityStatus.Untested)]
    [InlineData("sketchup", 2024, CompatibilityStatus.Untested)]
    public void EvaluatesHostVersionSupportHonestBounds(string hostId, int majorVersion, CompatibilityStatus expected)
    {
        var (status, _, _) = CompatibilityResolver.EvaluateHostVersionSupport(hostId, new Version(majorVersion, 0));
        Assert.Equal(expected, status);
    }
}

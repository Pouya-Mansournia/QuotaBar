using QuotaBar.App;

namespace QuotaBar.Windows.Tests;

public class ReleaseUpdaterTests
{
    [Theory]
    [InlineData("Windows-v1.0.3", "1.0.3")]
    [InlineData("v1.2.0", "1.2.0")]
    [InlineData("not-a-version", null)]
    [InlineData("Windows-v1.2", null)]
    public void ParsesPublishedVersion(string tag, string? expected)
    {
        Assert.Equal(expected, ReleaseUpdater.ParseReleaseVersion(tag)?.ToString(3));
    }
}

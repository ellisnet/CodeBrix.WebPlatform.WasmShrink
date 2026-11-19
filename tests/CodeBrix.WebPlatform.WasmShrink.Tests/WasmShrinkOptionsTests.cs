using SilverAssertions;
using Xunit;

namespace CodeBrix.WebPlatform.WasmShrink.Tests;

public class WasmShrinkOptionsTests
{
    [Fact]
    public void Level_is_smallest_file_by_default()
        => new WasmShrinkOptions().Level.Should().Be(WasmShrinkLevel.Oz);

    [Fact]
    public void KeepDebugInfo_is_off_by_default()
        => new WasmShrinkOptions().KeepDebugInfo.Should().BeFalse();

    [Fact]
    public void AdditionalArguments_is_empty_by_default()
        => new WasmShrinkOptions().AdditionalArguments.Should().BeEmpty();
}

using SilverAssertions;
using Xunit;

namespace CodeBrix.WebPlatform.WasmShrink.Tests;

public class WasmShrinkResultTests
{
    [Fact]
    public void Succeeded_is_true_for_exit_code_zero()
        => new WasmShrinkResult(0, "out", "err").Succeeded.Should().BeTrue();

    [Fact]
    public void Succeeded_is_false_for_a_non_zero_exit_code()
        => new WasmShrinkResult(1, "out", "err").Succeeded.Should().BeFalse();

    [Fact]
    public void output_is_never_null()
    {
        //Act
        var result = new WasmShrinkResult(0, null, null);

        //Assert
        result.StandardOutput.Should().BeEmpty();
        result.StandardError.Should().BeEmpty();
    }
}

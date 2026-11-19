using System;
using CodeBrix.WebPlatform.WasmShrink.Internal;
using SilverAssertions;
using Xunit;

namespace CodeBrix.WebPlatform.WasmShrink.Tests;

public class ArgumentBuilderTests
{
    [Theory]
    [InlineData(WasmShrinkLevel.O0, "-O0")]
    [InlineData(WasmShrinkLevel.O1, "-O1")]
    [InlineData(WasmShrinkLevel.O2, "-O2")]
    [InlineData(WasmShrinkLevel.O3, "-O3")]
    [InlineData(WasmShrinkLevel.O4, "-O4")]
    [InlineData(WasmShrinkLevel.Os, "-Os")]
    [InlineData(WasmShrinkLevel.Oz, "-Oz")]
    public void LevelSwitch_maps_every_level(WasmShrinkLevel level, string expected)
        => ArgumentBuilder.LevelSwitch(level).Should().Be(expected);

    [Fact]
    public void LevelSwitch_rejects_an_unknown_level()
    {
        //Arrange
        Action act = () => ArgumentBuilder.LevelSwitch((WasmShrinkLevel)99);

        //Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void Build_uses_smallest_file_and_strips_debug_info_by_default()
        => ArgumentBuilder.Build("in.wasm", "out.wasm", new WasmShrinkOptions())
            .Should().ContainInOrder("in.wasm", "-Oz", "--strip-debug", "-o", "out.wasm");

    [Fact]
    public void Build_default_command_line_has_exactly_five_arguments()
        => ArgumentBuilder.Build("in.wasm", "out.wasm", new WasmShrinkOptions()).Count.Should().Be(5);

    [Fact]
    public void Build_keeps_debug_info_when_asked()
    {
        //Arrange
        var options = new WasmShrinkOptions { KeepDebugInfo = true };

        //Act
        var arguments = ArgumentBuilder.Build("in.wasm", "out.wasm", options);

        //Assert
        arguments.Should().Contain("--debuginfo");
        arguments.Should().NotContain("--strip-debug");
    }

    [Fact]
    public void Build_places_additional_arguments_before_the_output()
    {
        //Arrange
        var options = new WasmShrinkOptions { Level = WasmShrinkLevel.O3 };
        options.AdditionalArguments.Add("--enable-bulk-memory");
        options.AdditionalArguments.Add("--enable-threads");

        //Act
        var arguments = ArgumentBuilder.Build("a b/in.wasm", "out.wasm", options);

        //Assert
        arguments.Should().ContainInOrder("a b/in.wasm", "-O3", "--strip-debug", "--enable-bulk-memory", "--enable-threads", "-o", "out.wasm");
    }

    [Fact]
    public void Build_rejects_an_empty_additional_argument()
    {
        //Arrange
        var options = new WasmShrinkOptions();
        options.AdditionalArguments.Add(" ");
        Action act = () => ArgumentBuilder.Build("in.wasm", "out.wasm", options);

        //Assert
        act.Should().Throw<ArgumentException>();
    }
}

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using CodeBrix.WebPlatform.WasmShrink.Internal;
using SilverAssertions;
using Xunit;

namespace CodeBrix.WebPlatform.WasmShrink.Tests;

public class ToolLocatorTests
{
    [Theory]
    [InlineData("linux", Architecture.X64, "linux-x64")]
    [InlineData("linux", Architecture.Arm64, "linux-arm64")]
    [InlineData("win", Architecture.X64, "win-x64")]
    [InlineData("osx", Architecture.Arm64, "osx-arm64")]
    [InlineData("osx", Architecture.X64, "osx-x64")]
    [InlineData("linux-musl", Architecture.X64, "linux-musl-x64")]
    [InlineData("linux", Architecture.RiscV64, "linux-riscv64")]
    public void ComposeRuntimeIdentifier_joins_system_and_architecture(string operatingSystem, Architecture architecture, string expected)
        => ToolLocator.ComposeRuntimeIdentifier(operatingSystem, architecture).Should().Be(expected);

    [Theory]
    [InlineData("linux-x64")]
    [InlineData("linux-arm64")]
    [InlineData("win-x64")]
    [InlineData("osx-arm64")]
    [InlineData("osx-x64")]
    public void IsSupported_accepts_the_five_build_platforms(string runtimeIdentifier)
        => ToolLocator.IsSupported(runtimeIdentifier).Should().BeTrue();

    [Theory]
    [InlineData("linux-riscv64")]
    [InlineData("win-arm64")]
    [InlineData("linux-musl-x64")]
    [InlineData("android-arm64")]
    [InlineData("LINUX-X64")]
    [InlineData("")]
    public void IsSupported_rejects_everything_else(string runtimeIdentifier)
        => ToolLocator.IsSupported(runtimeIdentifier).Should().BeFalse();

    [Fact]
    public void SupportedRuntimeIdentifiers_lists_exactly_five_platforms()
        => ToolLocator.SupportedRuntimeIdentifiers.Should().BeEquivalentTo(new[] { "linux-x64", "linux-arm64", "win-x64", "osx-arm64", "osx-x64" });

    [Theory]
    [InlineData("win-x64", "wasm-opt.exe")]
    [InlineData("linux-x64", "wasm-opt")]
    [InlineData("linux-arm64", "wasm-opt")]
    [InlineData("osx-arm64", "wasm-opt")]
    public void ExecutableFileName_has_an_extension_only_on_windows(string runtimeIdentifier, string expected)
        => ToolLocator.ExecutableFileName(runtimeIdentifier).Should().Be(expected);

    [Fact]
    public void ExpectedPath_is_a_folder_per_platform_beside_the_application()
        => ToolLocator.ExpectedPath("base", "linux-arm64").Should().Be(Path.Combine("base", "wasm-opt", "linux-arm64", "wasm-opt"));

    [Fact]
    public void CurrentRuntimeIdentifier_has_a_system_and_an_architecture()
        => ToolLocator.CurrentRuntimeIdentifier().Should().Contain("-");

    [Fact]
    public void Find_returns_null_when_the_program_is_not_there()
    {
        //Arrange
        using var folder = new TemporaryFolder();

        //Act
        var found = ToolLocator.Find(new[] { folder.Path }, "linux-x64");

        //Assert
        found.Should().BeNull();
    }

    [Fact]
    public void Find_skips_empty_folders_and_takes_the_first_that_has_the_program()
    {
        //Arrange
        using var empty = new TemporaryFolder();
        using var holder = new TemporaryFolder();
        var expected = PlaceProgram(holder.Path, "osx-arm64");

        //Act
        var found = ToolLocator.Find(new[] { null, string.Empty, empty.Path, holder.Path }, "osx-arm64");

        //Assert
        found.Should().Be(expected);
    }

    [Fact]
    public void Locate_names_the_supported_platforms_for_an_unsupported_one()
    {
        //Arrange
        using var folder = new TemporaryFolder();
        Action act = () => ToolLocator.Locate(new[] { folder.Path }, "linux-riscv64");

        //Assert
        act.Should().Throw<WasmShrinkException>()
            .WithMessage("*not provided for this platform ('linux-riscv64')*linux-x64*osx-x64*");
    }

    [Fact]
    public void Locate_says_where_it_looked_when_the_program_is_missing()
    {
        //Arrange
        using var folder = new TemporaryFolder();
        var expected = ToolLocator.ExpectedPath(folder.Path, "win-x64");
        Action act = () => ToolLocator.Locate(new[] { folder.Path }, "win-x64");

        //Assert
        act.Should().Throw<WasmShrinkException>().WithMessage("*'win-x64' was not found at '" + expected + "'*");
    }

    [Fact]
    public void Locate_returns_the_program_when_it_is_there()
    {
        //Arrange
        using var folder = new TemporaryFolder();
        var expected = PlaceProgram(folder.Path, "linux-x64");

        //Act
        var found = ToolLocator.Locate(new[] { folder.Path }, "linux-x64");

        //Assert
        found.Should().Be(expected);
    }

    [Fact]
    [UnsupportedOSPlatform("windows")]
    public void EnsureExecutable_adds_the_execute_permission()
    {
        Assert.SkipWhen(OperatingSystem.IsWindows(), "Windows has no execute permission.");

        //Arrange
        using var folder = new TemporaryFolder();
        var path = PlaceProgram(folder.Path, "linux-x64");
        File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);

        //Act
        ToolLocator.EnsureExecutable(path);

        //Assert
        (File.GetUnixFileMode(path) & UnixFileMode.UserExecute).Should().Be(UnixFileMode.UserExecute);
    }

    [Fact]
    [UnsupportedOSPlatform("windows")]
    public void EnsureExecutable_leaves_an_executable_file_as_it_is()
    {
        Assert.SkipWhen(OperatingSystem.IsWindows(), "Windows has no execute permission.");

        //Arrange
        using var folder = new TemporaryFolder();
        var path = PlaceProgram(folder.Path, "linux-x64");
        const UnixFileMode mode = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute;
        File.SetUnixFileMode(path, mode);

        //Act
        ToolLocator.EnsureExecutable(path);

        //Assert
        File.GetUnixFileMode(path).Should().Be(mode);
    }

    private static string PlaceProgram(string baseDirectory, string runtimeIdentifier)
    {
        var path = ToolLocator.ExpectedPath(baseDirectory, runtimeIdentifier);
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        File.WriteAllText(path, "not a real program");
        return path;
    }
}

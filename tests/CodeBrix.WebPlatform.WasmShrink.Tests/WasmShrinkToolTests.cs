using System;
using System.IO;
using System.Threading.Tasks;
using SilverAssertions;
using Xunit;

namespace CodeBrix.WebPlatform.WasmShrink.Tests;

/// <summary>
/// Runs the real wasm-opt program that the package ships for this machine. On a platform whose
/// program has not been built yet, these tests are skipped.
/// </summary>
public class WasmShrinkToolTests
{
    // The version of the wasm-opt programs committed under native_libraries/. Change it together
    // with them (see MAINTAINER-README.txt, UPGRADING THE VENDORED SOURCE).
    private const string BundledVersionLine = "wasm-opt version 133";

    // A small module written for these tests. It has an unused function and arithmetic that
    // folds away, so there is something for the optimizer to remove.
    private const string SampleModule = """
        (module
          (memory (export "memory") 1)
          (func $never_called (param $x i32) (result i32)
            (i32.add (local.get $x) (i32.const 1)))
          (func $add (export "add") (param $a i32) (param $b i32) (result i32)
            (local $t i32)
            (local.set $t (i32.add (local.get $a) (i32.const 0)))
            (i32.add (local.get $t) (i32.mul (local.get $b) (i32.const 1))))
          (func $answer (export "answer") (result i32)
            (i32.add (i32.const 40) (i32.const 2))))
        """;

    private static readonly byte[] WasmMagic = { 0x00, 0x61, 0x73, 0x6D };

    [Fact]
    public void ToolName_is_wasm_opt()
        => WasmShrinkTool.ToolName.Should().Be("wasm-opt");

    [Fact]
    public void SupportedRuntimeIdentifiers_lists_five_platforms()
        => WasmShrinkTool.SupportedRuntimeIdentifiers.Count.Should().Be(5);

    [Fact]
    public void ExecutableFileName_starts_with_the_tool_name()
        => WasmShrinkTool.ExecutableFileName.Should().StartWith("wasm-opt");

    [Fact]
    public void IsAvailable_implies_a_supported_platform()
        => (WasmShrinkTool.IsAvailable && !WasmShrinkTool.IsSupportedPlatform).Should().BeFalse();

    [Fact]
    public void GetExecutablePath_returns_an_existing_file_in_the_platform_folder()
    {
        SkipUnlessAvailable();

        //Act
        var path = WasmShrinkTool.GetExecutablePath();

        //Assert
        File.Exists(path).Should().BeTrue();
        Path.GetFileName(path).Should().Be(WasmShrinkTool.ExecutableFileName);
        Path.GetFileName(Path.GetDirectoryName(path)).Should().Be(WasmShrinkTool.CurrentRuntimeIdentifier);
    }

    [Fact]
    public void GetToolDirectory_holds_only_the_program_and_its_licence_texts()
    {
        SkipUnlessAvailable();

        //Act
        var files = Directory.GetFiles(WasmShrinkTool.GetToolDirectory());

        //Assert
        files.Should().Contain(WasmShrinkTool.GetExecutablePath());
        foreach (var file in files)
        {
            var name = Path.GetFileName(file);
            (name == WasmShrinkTool.ExecutableFileName || name.StartsWith("LICENSE-", StringComparison.Ordinal)).Should().BeTrue();
        }
    }

    [Fact]
    public void GetToolDirectory_for_the_current_platform_matches_the_parameterless_form()
    {
        SkipUnlessAvailable();

        //Act
        var directory = WasmShrinkTool.GetToolDirectory(WasmShrinkTool.CurrentRuntimeIdentifier);

        //Assert
        directory.Should().Be(WasmShrinkTool.GetToolDirectory());
    }

    [Fact]
    public void GetToolDirectory_rejects_an_unsupported_platform()
    {
        //Arrange
        Action act = () => WasmShrinkTool.GetToolDirectory("linux-riscv64");

        //Assert
        act.Should().Throw<WasmShrinkException>().WithMessage("*not provided for this platform*");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    public void GetToolDirectory_rejects_an_empty_platform(string runtimeIdentifier)
    {
        //Arrange
        Action act = () => WasmShrinkTool.GetToolDirectory(runtimeIdentifier);

        //Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void PrependToPath_puts_the_tool_folder_first()
    {
        SkipUnlessAvailable();

        //Act
        var path = WasmShrinkTool.PrependToPath("existing");

        //Assert
        path.Should().Be(WasmShrinkTool.GetToolDirectory() + Path.PathSeparator + "existing");
    }

    [Fact]
    public void PrependToPath_uses_the_process_path_when_none_is_given()
    {
        SkipUnlessAvailable();

        //Act
        var path = WasmShrinkTool.PrependToPath();

        //Assert
        path.Should().StartWith(WasmShrinkTool.GetToolDirectory());
    }

    [Fact]
    public async Task GetVersionAsync_reports_the_bundled_version()
    {
        SkipUnlessAvailable();

        //Act
        var version = await WasmShrinkTool.GetVersionAsync(TestContext.Current.CancellationToken);

        //Assert
        version.Should().Be(BundledVersionLine);
    }

    [Fact]
    public async Task RunAsync_rejects_null_arguments()
    {
        //Arrange
        Func<Task> act = () => WasmShrinkTool.RunAsync(null, null, TestContext.Current.CancellationToken);

        //Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task RunAsync_returns_a_failure_instead_of_throwing()
    {
        SkipUnlessAvailable();

        //Arrange
        using var folder = new TemporaryFolder();

        //Act
        var result = await WasmShrinkTool.RunAsync(new[] { folder.File("missing.wasm"), "-o", folder.File("out.wasm") }, null, TestContext.Current.CancellationToken);

        //Assert
        result.Succeeded.Should().BeFalse();
        result.StandardError.Should().NotBeEmpty();
    }

    [Fact]
    public async Task RunAsync_runs_in_the_given_working_folder()
    {
        SkipUnlessAvailable();

        //Arrange
        using var folder = new TemporaryFolder();
        await File.WriteAllTextAsync(folder.File("sample.wat"), SampleModule, TestContext.Current.CancellationToken);

        //Act
        var result = await WasmShrinkTool.RunAsync(new[] { "sample.wat", "-o", "sample.wasm" }, folder.Path, TestContext.Current.CancellationToken);

        //Assert
        result.Succeeded.Should().BeTrue();
        File.Exists(folder.File("sample.wasm")).Should().BeTrue();
    }

    [Fact]
    public async Task ShrinkAsync_writes_a_webassembly_binary()
    {
        SkipUnlessAvailable();

        //Arrange
        using var folder = new TemporaryFolder();
        var input = folder.File("sample.wat");
        var output = folder.File("sample.wasm");
        await File.WriteAllTextAsync(input, SampleModule, TestContext.Current.CancellationToken);

        //Act
        var result = await WasmShrinkTool.ShrinkAsync(input, output, null, TestContext.Current.CancellationToken);

        //Assert
        result.Succeeded.Should().BeTrue();
        var bytes = await File.ReadAllBytesAsync(output, TestContext.Current.CancellationToken);
        bytes.AsSpan(0, 4).ToArray().Should().Equal(WasmMagic);
    }

    [Fact]
    public async Task ShrinkAsync_makes_the_file_smaller_than_no_optimization()
    {
        SkipUnlessAvailable();

        //Arrange
        using var folder = new TemporaryFolder();
        var input = folder.File("sample.wat");
        await File.WriteAllTextAsync(input, SampleModule, TestContext.Current.CancellationToken);

        //Act
        await WasmShrinkTool.ShrinkAsync(input, folder.File("o0.wasm"), new WasmShrinkOptions { Level = WasmShrinkLevel.O0 }, TestContext.Current.CancellationToken);
        await WasmShrinkTool.ShrinkAsync(input, folder.File("oz.wasm"), new WasmShrinkOptions { Level = WasmShrinkLevel.Oz }, TestContext.Current.CancellationToken);

        //Assert
        new FileInfo(folder.File("oz.wasm")).Length.Should().BeLessThan(new FileInfo(folder.File("o0.wasm")).Length);
    }

    [Fact]
    public async Task ShrinkAsync_can_shrink_a_binary_file_in_place()
    {
        SkipUnlessAvailable();

        //Arrange
        using var folder = new TemporaryFolder();
        var wat = folder.File("sample.wat");
        var wasm = folder.File("sample.wasm");
        await File.WriteAllTextAsync(wat, SampleModule, TestContext.Current.CancellationToken);
        await WasmShrinkTool.ShrinkAsync(wat, wasm, new WasmShrinkOptions { Level = WasmShrinkLevel.O0 }, TestContext.Current.CancellationToken);
        var before = new FileInfo(wasm).Length;

        //Act
        await WasmShrinkTool.ShrinkAsync(wasm, wasm, null, TestContext.Current.CancellationToken);

        //Assert
        new FileInfo(wasm).Length.Should().BeLessThan(before);
    }

    [Fact]
    public async Task ShrinkAsync_keeps_function_names_with_debug_info()
    {
        SkipUnlessAvailable();

        //Arrange
        using var folder = new TemporaryFolder();
        var input = folder.File("sample.wat");
        await File.WriteAllTextAsync(input, SampleModule, TestContext.Current.CancellationToken);

        //Act
        await WasmShrinkTool.ShrinkAsync(input, folder.File("names.wasm"), new WasmShrinkOptions { KeepDebugInfo = true }, TestContext.Current.CancellationToken);
        await WasmShrinkTool.ShrinkAsync(input, folder.File("stripped.wasm"), new WasmShrinkOptions { KeepDebugInfo = false }, TestContext.Current.CancellationToken);

        //Assert
        new FileInfo(folder.File("names.wasm")).Length.Should().BeGreaterThan(new FileInfo(folder.File("stripped.wasm")).Length);
    }

    [Fact]
    public async Task ShrinkAsync_accepts_the_feature_switches_a_frontend_build_passes()
    {
        SkipUnlessAvailable();

        //Arrange
        using var folder = new TemporaryFolder();
        var input = folder.File("sample.wat");
        await File.WriteAllTextAsync(input, SampleModule, TestContext.Current.CancellationToken);
        var options = new WasmShrinkOptions();
        options.AdditionalArguments.Add("--enable-reference-types");
        options.AdditionalArguments.Add("--enable-bulk-memory");
        options.AdditionalArguments.Add("--enable-mutable-globals");
        options.AdditionalArguments.Add("--enable-nontrapping-float-to-int");
        options.AdditionalArguments.Add("--enable-threads");
        options.AdditionalArguments.Add("--memory-packing");

        //Act
        var result = await WasmShrinkTool.ShrinkAsync(input, folder.File("out.wasm"), options, TestContext.Current.CancellationToken);

        //Assert
        result.Succeeded.Should().BeTrue();
    }

    [Fact]
    public async Task ShrinkAsync_reports_what_the_program_said_when_it_fails()
    {
        SkipUnlessAvailable();

        //Arrange
        using var folder = new TemporaryFolder();
        var input = folder.File("broken.wat");
        await File.WriteAllTextAsync(input, "(module (func (result i32)))", TestContext.Current.CancellationToken);
        Func<Task> act = () => WasmShrinkTool.ShrinkAsync(input, folder.File("out.wasm"), null, TestContext.Current.CancellationToken);

        //Assert
        await act.Should().ThrowAsync<WasmShrinkException>().WithMessage("*wasm-opt failed with exit code*");
    }

    [Fact]
    public async Task ShrinkAsync_rejects_a_missing_input_file()
    {
        //Arrange
        using var folder = new TemporaryFolder();
        Func<Task> act = () => WasmShrinkTool.ShrinkAsync(folder.File("missing.wasm"), folder.File("out.wasm"), null, TestContext.Current.CancellationToken);

        //Assert
        await act.Should().ThrowAsync<FileNotFoundException>();
    }

    [Theory]
    [InlineData("", "out.wasm")]
    [InlineData("in.wasm", " ")]
    public async Task ShrinkAsync_rejects_an_empty_path(string inputPath, string outputPath)
    {
        //Arrange
        Func<Task> act = () => WasmShrinkTool.ShrinkAsync(inputPath, outputPath, null, TestContext.Current.CancellationToken);

        //Assert
        await act.Should().ThrowAsync<ArgumentException>();
    }

    private static void SkipUnlessAvailable()
        => Assert.SkipUnless(
            WasmShrinkTool.IsAvailable,
            $"The package does not include wasm-opt for '{WasmShrinkTool.CurrentRuntimeIdentifier}' yet.");
}

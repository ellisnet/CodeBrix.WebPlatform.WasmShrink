using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using CodeBrix.WebPlatform.WasmShrink.Internal;

namespace CodeBrix.WebPlatform.WasmShrink;

/// <summary>
/// The wasm-opt program that ships in this package: where the copy for the current machine
/// is, a folder to put on <c>PATH</c> so another build tool finds it, and methods that run it.
/// </summary>
/// <remarks>
/// The package copies the programs beside the application as
/// <c>wasm-opt/&lt;platform&gt;/wasm-opt</c> (<c>wasm-opt.exe</c> on Windows). Nothing has to be
/// installed on the machine.
/// </remarks>
public static class WasmShrinkTool
{
    /// <summary>The name of the program, without a file extension: <c>wasm-opt</c>.</summary>
    public const string ToolName = "wasm-opt";

    /// <summary>The platforms the package is built for, as .NET runtime identifiers.</summary>
    public static IReadOnlyList<string> SupportedRuntimeIdentifiers => ToolLocator.SupportedRuntimeIdentifiers;

    /// <summary>
    /// The runtime identifier of the machine this process is running on, for example
    /// <c>linux-x64</c>. It is reported even when the platform is not a supported one.
    /// </summary>
    public static string CurrentRuntimeIdentifier => ToolLocator.CurrentRuntimeIdentifier();

    /// <summary><c>true</c> when the current machine is one of <see cref="SupportedRuntimeIdentifiers"/>.</summary>
    public static bool IsSupportedPlatform => ToolLocator.IsSupported(CurrentRuntimeIdentifier);

    /// <summary>
    /// <c>true</c> when the program for the current machine is present beside the application,
    /// so the other members of this class can be used. Never throws.
    /// </summary>
    public static bool IsAvailable
        => IsSupportedPlatform && ToolLocator.Find(BaseDirectories(), CurrentRuntimeIdentifier) != null;

    /// <summary>The file name of the program on the current machine: <c>wasm-opt.exe</c> on Windows, <c>wasm-opt</c> elsewhere.</summary>
    public static string ExecutableFileName => ToolLocator.ExecutableFileName(CurrentRuntimeIdentifier);

    /// <summary>
    /// Returns the full path of the program for the current machine, after making sure it can
    /// be started (on Linux and macOS it is given the execute permission if it lacks it).
    /// </summary>
    /// <returns>The full path of <c>wasm-opt</c> (<c>wasm-opt.exe</c> on Windows).</returns>
    /// <exception cref="WasmShrinkException">
    /// The platform is not supported, the program for it is not beside the application, or it
    /// could not be made executable.
    /// </exception>
    public static string GetExecutablePath()
    {
        var path = ToolLocator.Locate(BaseDirectories(), CurrentRuntimeIdentifier);
        ToolLocator.EnsureExecutable(path);
        return path;
    }

    /// <summary>
    /// Returns the folder that holds the program for the current machine. The folder contains
    /// that program and its licence texts and nothing else, so it can be put first on
    /// <c>PATH</c> for a build tool that looks <c>wasm-opt</c> up by name.
    /// </summary>
    /// <returns>The full path of the folder.</returns>
    /// <exception cref="WasmShrinkException">
    /// The platform is not supported, the program for it is not beside the application, or it
    /// could not be made executable.
    /// </exception>
    public static string GetToolDirectory()
        => Path.GetDirectoryName(GetExecutablePath());

    /// <summary>
    /// Returns the folder that holds the program for another platform - for example to copy the
    /// Linux program into a build container started from Windows or macOS. The package copies
    /// every platform's program beside the application, so any supported one can be asked for.
    /// </summary>
    /// <param name="runtimeIdentifier">One of <see cref="SupportedRuntimeIdentifiers"/>, for example <c>linux-x64</c>.</param>
    /// <returns>The full path of the folder, which holds only that program and its licence texts.</returns>
    /// <exception cref="ArgumentException"><paramref name="runtimeIdentifier"/> is empty.</exception>
    /// <exception cref="WasmShrinkException">
    /// The platform is not supported, or its program is not beside the application.
    /// </exception>
    /// <remarks>
    /// On Linux and macOS the file is given the execute permission if it lacks it. On Windows
    /// there is no such permission to give: set it after copying the file to its destination.
    /// </remarks>
    public static string GetToolDirectory(string runtimeIdentifier)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(runtimeIdentifier);
        var path = ToolLocator.Locate(BaseDirectories(), runtimeIdentifier);
        ToolLocator.EnsureExecutable(path);
        return Path.GetDirectoryName(path);
    }

    /// <summary>
    /// Returns the value of <c>PATH</c> with the program's folder placed first, for the
    /// environment of a build tool that is about to be started.
    /// </summary>
    /// <param name="existingPath">
    /// The <c>PATH</c> to extend. When <c>null</c>, the current process's <c>PATH</c> is used.
    /// </param>
    /// <returns>The folder from <see cref="GetToolDirectory()"/>, the platform's separator, then the existing value.</returns>
    /// <exception cref="WasmShrinkException">See <see cref="GetToolDirectory()"/>.</exception>
    public static string PrependToPath(string existingPath = null)
    {
        var directory = GetToolDirectory();
        var current = existingPath ?? Environment.GetEnvironmentVariable("PATH");
        return string.IsNullOrEmpty(current) ? directory : directory + Path.PathSeparator + current;
    }

    /// <summary>
    /// Runs the program with exactly the given arguments and returns what it reported. A
    /// non-zero exit code is returned, not thrown.
    /// </summary>
    /// <param name="arguments">The command-line arguments, one per item; no quoting is needed.</param>
    /// <param name="workingDirectory">The folder to run in, or <c>null</c> for the current one.</param>
    /// <param name="cancellationToken">Cancelling stops the program.</param>
    /// <returns>The exit code and everything written to standard output and standard error.</returns>
    /// <exception cref="ArgumentNullException"><paramref name="arguments"/> is <c>null</c>.</exception>
    /// <exception cref="WasmShrinkException">The program could not be found or started.</exception>
    public static Task<WasmShrinkResult> RunAsync(
        IEnumerable<string> arguments,
        string workingDirectory = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(arguments);
        return ProcessRunner.RunAsync(GetExecutablePath(), arguments, workingDirectory, cancellationToken);
    }

    /// <summary>Asks the program for its version line, for example <c>wasm-opt version 100</c>.</summary>
    /// <param name="cancellationToken">Cancelling stops the program.</param>
    /// <returns>The first line the program prints for <c>--version</c>, trimmed.</returns>
    /// <exception cref="WasmShrinkException">The program could not be found or started, or it reported a failure.</exception>
    public static async Task<string> GetVersionAsync(CancellationToken cancellationToken = default)
    {
        var result = await RunAsync(new[] { "--version" }, null, cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded)
        {
            throw new WasmShrinkException($"wasm-opt --version failed with exit code {result.ExitCode}: {result.StandardError.Trim()}");
        }

        var text = result.StandardOutput.Trim();
        var lineEnd = text.IndexOf('\n');
        return lineEnd < 0 ? text : text.Substring(0, lineEnd).Trim();
    }

    /// <summary>
    /// Shrinks a WebAssembly file. The input may be a binary <c>.wasm</c> file or a text
    /// <c>.wat</c> file; the output is a binary file. Input and output may be the same path.
    /// </summary>
    /// <param name="inputPath">The file to read.</param>
    /// <param name="outputPath">The file to write; its folder must exist.</param>
    /// <param name="options">The optimization choices, or <c>null</c> for the defaults (smallest file, debug information removed).</param>
    /// <param name="cancellationToken">Cancelling stops the program.</param>
    /// <returns>What the program reported; <see cref="WasmShrinkResult.Succeeded"/> is always <c>true</c>.</returns>
    /// <exception cref="ArgumentException"><paramref name="inputPath"/> or <paramref name="outputPath"/> is empty.</exception>
    /// <exception cref="FileNotFoundException"><paramref name="inputPath"/> does not exist.</exception>
    /// <exception cref="WasmShrinkException">
    /// The program could not be found or started, or it reported a failure; the message carries
    /// what it wrote to standard error.
    /// </exception>
    public static async Task<WasmShrinkResult> ShrinkAsync(
        string inputPath,
        string outputPath,
        WasmShrinkOptions options = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(inputPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(outputPath);

        if (!File.Exists(inputPath))
        {
            throw new FileNotFoundException($"The WebAssembly file to shrink was not found: '{inputPath}'.", inputPath);
        }

        var arguments = ArgumentBuilder.Build(inputPath, outputPath, options ?? new WasmShrinkOptions());
        var result = await RunAsync(arguments, null, cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded)
        {
            throw new WasmShrinkException(
                $"wasm-opt failed with exit code {result.ExitCode} while shrinking '{inputPath}': {result.StandardError.Trim()}");
        }

        return result;
    }

    private static List<string> BaseDirectories()
    {
        var directories = new List<string> { AppContext.BaseDirectory };

        var assemblyLocation = typeof(WasmShrinkTool).Assembly.Location;
        if (!string.IsNullOrEmpty(assemblyLocation))
        {
            var assemblyDirectory = Path.GetDirectoryName(assemblyLocation);
            if (!string.IsNullOrEmpty(assemblyDirectory))
            {
                directories.Add(assemblyDirectory);
            }
        }

        return directories;
    }
}

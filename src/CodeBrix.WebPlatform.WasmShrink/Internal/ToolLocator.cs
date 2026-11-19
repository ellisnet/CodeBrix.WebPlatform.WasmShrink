using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

namespace CodeBrix.WebPlatform.WasmShrink.Internal;

/// <summary>
/// Works out which wasm-opt program belongs to a machine and where it sits beside the
/// application: <c>&lt;application folder&gt;/wasm-opt/&lt;rid&gt;/wasm-opt[.exe]</c>.
/// </summary>
internal static class ToolLocator
{
    /// <summary>The folder, beside the application, that holds one sub-folder per platform.</summary>
    internal const string ToolFolderName = "wasm-opt";

    /// <summary>The platforms the package is built for.</summary>
    internal static readonly IReadOnlyList<string> SupportedRuntimeIdentifiers = new[]
    {
        "linux-x64",
        "linux-arm64",
        "win-x64",
        "osx-arm64",
        "osx-x64",
    };

    /// <summary>The runtime identifier of the machine this process is running on.</summary>
    internal static string CurrentRuntimeIdentifier()
        => ComposeRuntimeIdentifier(CurrentOperatingSystem(), RuntimeInformation.ProcessArchitecture);

    /// <summary>Joins an operating-system name and a processor architecture into a runtime identifier.</summary>
    internal static string ComposeRuntimeIdentifier(string operatingSystem, Architecture architecture)
        => operatingSystem + "-" + architecture.ToString().ToLowerInvariant();

    /// <summary><c>true</c> when the package is built for <paramref name="runtimeIdentifier"/>.</summary>
    internal static bool IsSupported(string runtimeIdentifier)
    {
        foreach (var supported in SupportedRuntimeIdentifiers)
        {
            if (string.Equals(supported, runtimeIdentifier, StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>The file name of the program on a platform: <c>wasm-opt.exe</c> on Windows, <c>wasm-opt</c> elsewhere.</summary>
    internal static string ExecutableFileName(string runtimeIdentifier)
        => runtimeIdentifier.StartsWith("win-", StringComparison.Ordinal) ? "wasm-opt.exe" : "wasm-opt";

    /// <summary>The folder that holds the program for a platform, beside an application in <paramref name="baseDirectory"/>.</summary>
    internal static string ToolDirectory(string baseDirectory, string runtimeIdentifier)
        => Path.Combine(baseDirectory, ToolFolderName, runtimeIdentifier);

    /// <summary>Where the program for a platform is expected, beside an application in <paramref name="baseDirectory"/>.</summary>
    internal static string ExpectedPath(string baseDirectory, string runtimeIdentifier)
        => Path.Combine(ToolDirectory(baseDirectory, runtimeIdentifier), ExecutableFileName(runtimeIdentifier));

    /// <summary>
    /// Finds the program for <paramref name="runtimeIdentifier"/> in the first of
    /// <paramref name="baseDirectories"/> that has it, or returns <c>null</c>.
    /// </summary>
    internal static string Find(IEnumerable<string> baseDirectories, string runtimeIdentifier)
    {
        foreach (var baseDirectory in baseDirectories)
        {
            if (string.IsNullOrEmpty(baseDirectory))
            {
                continue;
            }

            var candidate = ExpectedPath(baseDirectory, runtimeIdentifier);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    /// <summary>
    /// Finds the program for <paramref name="runtimeIdentifier"/>, or throws a
    /// <see cref="WasmShrinkException"/> that says whether the platform is unsupported or the
    /// file is simply not there.
    /// </summary>
    internal static string Locate(IReadOnlyList<string> baseDirectories, string runtimeIdentifier)
    {
        if (!IsSupported(runtimeIdentifier))
        {
            throw new WasmShrinkException(
                $"wasm-opt is not provided for this platform ('{runtimeIdentifier}'). " +
                $"The supported platforms are: {string.Join(", ", SupportedRuntimeIdentifiers)}.");
        }

        var found = Find(baseDirectories, runtimeIdentifier);
        if (found != null)
        {
            return found;
        }

        var expected = baseDirectories.Count > 0 ? ExpectedPath(baseDirectories[0], runtimeIdentifier) : ExpectedPath(".", runtimeIdentifier);
        throw new WasmShrinkException(
            $"wasm-opt for '{runtimeIdentifier}' was not found at '{expected}'. " +
            "Either this version of the package does not include that platform yet, or the " +
            $"'{ToolFolderName}' folder was not copied beside the application - rebuild the project " +
            "that references the CodeBrix.WebPlatform.WasmShrink package.");
    }

    /// <summary>
    /// Gives the file the execute permission on Linux and macOS. A NuGet package does not carry
    /// that permission, so a freshly restored copy cannot be started until this has run. Does
    /// nothing on Windows, or when the permission is already there.
    /// </summary>
    internal static void EnsureExecutable(string path)
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        const UnixFileMode execute = UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute;

        try
        {
            var mode = File.GetUnixFileMode(path);
            if ((mode & UnixFileMode.UserExecute) != 0)
            {
                return;
            }

            File.SetUnixFileMode(path, mode | execute);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw new WasmShrinkException(
                $"'{path}' could not be made executable: {exception.Message} " +
                "Give the file the execute permission (chmod +x), or build the application into a folder that can be written to.",
                exception);
        }
    }

    private static string CurrentOperatingSystem()
    {
        if (OperatingSystem.IsWindows())
        {
            return "win";
        }

        if (OperatingSystem.IsMacOS())
        {
            return "osx";
        }

        if (OperatingSystem.IsLinux())
        {
            // The programs are linked against glibc. A musl-based distribution reports itself as
            // "linux-musl-<arch>", which is deliberately not in the supported list.
            return RuntimeInformation.RuntimeIdentifier.StartsWith("linux-musl", StringComparison.Ordinal) ? "linux-musl" : "linux";
        }

        var identifier = RuntimeInformation.RuntimeIdentifier;
        var dash = identifier.LastIndexOf('-');
        return dash > 0 ? identifier.Substring(0, dash) : identifier;
    }
}

================================================================================
AGENT-README: CodeBrix.WebPlatform.WasmShrink
A Guide for AI Coding Agents — CONSUMING the CodeBrix.WebPlatform.WasmShrink.ApacheLicenseForever NuGet package
================================================================================

OVERVIEW
========
CodeBrix.WebPlatform.WasmShrink gives a build the `wasm-opt` WebAssembly
optimizer without anything being installed on the machine. The package holds:

  - the wasm-opt program for each supported build platform, and
  - a .NET 10 library (one static class, WasmShrinkTool) that finds the copy
    for the current machine, makes it runnable, and runs it.

It is a BUILD-TIME package. It is referenced by the program that builds an
application (for a CodeBrix.WebPlatform application, the program that builds
the frontend). It is not referenced by a backend, is not deployed with the
built web application, and has no purpose at run time.

Two ways to use it:

  1. Shrink a file yourself: WasmShrinkTool.ShrinkAsync(input, output).
  2. Let another build tool do the shrinking: that tool looks `wasm-opt` up on
     PATH, so start it with WasmShrinkTool.PrependToPath() as its PATH (or add
     WasmShrinkTool.GetToolDirectory() to PATH yourself).

Provenance: the wasm-opt programs are built from the Binaryen project's source
(Apache License 2.0), unmodified. THIRD-PARTY-NOTICES.txt in the package has
the details and the licence texts.


INSTALLATION
============
    dotnet add package CodeBrix.WebPlatform.WasmShrink.ApacheLicenseForever

  PackageId:   CodeBrix.WebPlatform.WasmShrink.ApacheLicenseForever
  Assembly:    CodeBrix.WebPlatform.WasmShrink
  Namespace:   CodeBrix.WebPlatform.WasmShrink
  License:     Apache-2.0
  Target:      .NET 10 (usable from projects targeting .NET 10 or later)
  Dependencies: none other than .NET.

There is no package named plain "CodeBrix.WebPlatform.WasmShrink".

Supported build platforms (.NET runtime identifiers):

    linux-x64     linux-arm64     win-x64     osx-arm64     osx-x64

Linux means a distribution that uses the GNU C library (Debian-based
distributions, for example). A musl-based distribution is not supported.
Nothing else is required: no installed wasm-opt, no Node.js, no other tool.

WHAT THE PACKAGE DOES TO YOUR PROJECT. When the project is built, the package
copies the programs into the project's output folder:

    <output folder>/wasm-opt/<runtime identifier>/wasm-opt        (.exe on Windows)
    <output folder>/wasm-opt/<runtime identifier>/LICENSE-*.txt

All platforms are copied, so the output can be moved to another supported
machine. The copy also happens when the package arrives through another
package that depends on it. WasmShrinkTool looks in that folder, beside the
running application; you never pass it a path.


KEY NAMESPACES / USINGS
=======================
    using CodeBrix.WebPlatform.WasmShrink;

That one namespace holds every public type. There are no sub-namespaces to
import.


CORE API REFERENCE
==================

WasmShrinkTool (static class)
-----------------------------
  const string ToolName = "wasm-opt"
      The program's name without a file extension.

  static IReadOnlyList<string> SupportedRuntimeIdentifiers
      The five platforms listed above.

  static string CurrentRuntimeIdentifier
      The current machine, e.g. "linux-x64". Reported even when unsupported
      (e.g. "linux-musl-x64", "win-arm64").

  static bool IsSupportedPlatform
      CurrentRuntimeIdentifier is one of SupportedRuntimeIdentifiers.

  static bool IsAvailable
      Supported platform AND the program is present beside the application.
      Never throws. Check it before the members below when you want to skip
      shrinking instead of failing.

  static string ExecutableFileName
      "wasm-opt.exe" on Windows, "wasm-opt" elsewhere.

  static string GetExecutablePath()
      Full path of the program for this machine. On Linux and macOS it first
      gives the file the execute permission if it lacks it (a NuGet package
      does not carry that permission). Throws WasmShrinkException.

  static string GetToolDirectory()
      The folder holding the program. It contains only that program and its
      licence texts, so it is safe to put on PATH. Throws WasmShrinkException.

  static string GetToolDirectory(string runtimeIdentifier)
      The same for ANOTHER supported platform, e.g. "linux-x64" - for copying
      the Linux program into a build container started from Windows or macOS.
      Every platform's program is beside the application. On Windows the
      execute permission cannot be set; set it after copying the file.

  static string PrependToPath(string existingPath = null)
      GetToolDirectory() + the platform's PATH separator + existingPath.
      With null, the current process's PATH is used. Returns a value; it does
      not change any environment. Throws WasmShrinkException.

  static Task<WasmShrinkResult> RunAsync(
      IEnumerable<string> arguments,
      string workingDirectory = null,
      CancellationToken cancellationToken = default)
      Runs the program with exactly those arguments (one per item, no quoting).
      A non-zero exit code is RETURNED in the result, not thrown. Cancelling
      stops the program and throws OperationCanceledException.

  static Task<string> GetVersionAsync(CancellationToken cancellationToken = default)
      The program's version line. Throws WasmShrinkException on failure.

  static Task<WasmShrinkResult> ShrinkAsync(
      string inputPath,
      string outputPath,
      WasmShrinkOptions options = null,
      CancellationToken cancellationToken = default)
      Shrinks a WebAssembly file. Input: binary .wasm or text .wat. Output:
      binary. Input and output may be the same path. With null options: the
      smallest file, debug information removed. THROWS WasmShrinkException
      when the program reports a failure (the message carries its error
      output), FileNotFoundException when the input is missing, and
      ArgumentException for an empty path.

WasmShrinkOptions (class)
-------------------------
  WasmShrinkLevel Level { get; set; }          default WasmShrinkLevel.Oz
  bool KeepDebugInfo { get; set; }             default false
      false -> "--strip-debug"; true -> "--debuginfo" (keeps function names).
  IList<string> AdditionalArguments { get; }   empty by default
      Extra wasm-opt arguments, placed after the ones above.

  The command line ShrinkAsync builds is:
      <input> <level switch> <--strip-debug | --debuginfo> <additional...> -o <output>

WasmShrinkLevel (enum)
----------------------
  O0   no optimization passes        O1   quick and light
  O2   most optimizations, speed     O3   more thorough, speed
  O4   most thorough, speed          Os   smaller file
  Oz   smallest file (default)

WasmShrinkResult (class)
------------------------
  int ExitCode                zero means success
  string StandardOutput       never null
  string StandardError        never null; wasm-opt reports errors here
  bool Succeeded              ExitCode == 0

WasmShrinkException (class, derives from Exception)
---------------------------------------------------
Thrown when:
  - the current platform is not supported (the message lists the supported
    ones);
  - the program for this platform is not beside the application (this version
    of the package does not include that platform yet, or the wasm-opt folder
    was not copied - rebuild the referencing project);
  - the file could not be made executable (read-only folder);
  - the program could not be started;
  - ShrinkAsync or GetVersionAsync: the program exited with a non-zero code.


COMPLETE EXAMPLES
=================

1. Shrink in place, with the defaults

    using CodeBrix.WebPlatform.WasmShrink;

    await WasmShrinkTool.ShrinkAsync("app.wasm", "app.wasm");

2. Shrink only for a release build, keep names in a debug build

    using CodeBrix.WebPlatform.WasmShrink;

    static async Task ShrinkAsync(string wasmPath, bool release, CancellationToken cancellationToken)
    {
        if (!release)
        {
            return;   // shrinking takes time and removes names; skip it while developing
        }

        var before = new FileInfo(wasmPath).Length;
        await WasmShrinkTool.ShrinkAsync(wasmPath, wasmPath, cancellationToken: cancellationToken);
        var after = new FileInfo(wasmPath).Length;
        Console.WriteLine($"{wasmPath}: {before} -> {after} bytes");
    }

3. A module that uses newer WebAssembly features

    using CodeBrix.WebPlatform.WasmShrink;

    var options = new WasmShrinkOptions();
    options.AdditionalArguments.Add("--enable-bulk-memory");
    options.AdditionalArguments.Add("--enable-reference-types");
    await WasmShrinkTool.ShrinkAsync("app.wasm", "app.min.wasm", options);

4. Hand the optimizer to another build tool through PATH

    using System.Diagnostics;
    using CodeBrix.WebPlatform.WasmShrink;

    var startInfo = new ProcessStartInfo("my-build-tool") { UseShellExecute = false };
    startInfo.ArgumentList.Add("build");
    startInfo.Environment["PATH"] = WasmShrinkTool.PrependToPath();
    using var process = Process.Start(startInfo);
    await process.WaitForExitAsync();

5. Run with your own arguments and inspect the result

    using CodeBrix.WebPlatform.WasmShrink;

    var result = await WasmShrinkTool.RunAsync(new[] { "app.wasm", "--metrics" });
    Console.WriteLine(result.Succeeded ? result.StandardOutput : result.StandardError);

6. Degrade gracefully where the program is not available

    using CodeBrix.WebPlatform.WasmShrink;

    if (WasmShrinkTool.IsAvailable)
    {
        await WasmShrinkTool.ShrinkAsync(path, path);
    }
    else
    {
        Console.WriteLine($"wasm-opt is not available for {WasmShrinkTool.CurrentRuntimeIdentifier}; the file is left as it is.");
    }


MINIMUM VIABLE PROJECT TEMPLATE
===============================
shrink.csproj

    <Project Sdk="Microsoft.NET.Sdk">
      <PropertyGroup>
        <OutputType>Exe</OutputType>
        <TargetFramework>net10.0</TargetFramework>
      </PropertyGroup>
      <ItemGroup>
        <PackageReference Include="CodeBrix.WebPlatform.WasmShrink.ApacheLicenseForever" Version="*" />
      </ItemGroup>
    </Project>

  (Replace Version="*" with the version you install.)

Program.cs

    using System;
    using System.IO;
    using CodeBrix.WebPlatform.WasmShrink;

    if (args.Length != 2)
    {
        Console.Error.WriteLine("usage: shrink <input.wasm> <output.wasm>");
        return 2;
    }

    try
    {
        await WasmShrinkTool.ShrinkAsync(args[0], args[1]);
        Console.WriteLine($"{new FileInfo(args[0]).Length} -> {new FileInfo(args[1]).Length} bytes");
        return 0;
    }
    catch (WasmShrinkException exception)
    {
        Console.Error.WriteLine(exception.Message);
        return 1;
    }


PERFORMANCE TIPS
================
  - Shrinking a multi-megabyte file at Oz or O4 takes noticeable time. Do it
    for release builds; skip it (or use O1) while developing.
  - Shrink BEFORE a file name is derived from the file's content (a hash in
    the name for browser caching). Shrinking afterwards leaves a name that no
    longer matches the contents.
  - The program uses several processor cores by itself; running many copies at
    once on one machine gains little.
  - Shrinking in place (input == output) avoids a second copy on disk.


COMMON PITFALLS TO AVOID
========================
  - "wasm-opt ... was not found at ...". The wasm-opt folder is copied when
    the REFERENCING project is built. Rebuild it. If you copy your build
    program somewhere else, copy the wasm-opt folder with it. A platform that
    this version of the package does not include yet gives the same message.
  - Referencing the package from the backend or the web application. It is a
    build-time package; reference it only from the program that builds.
  - Passing one string with several arguments ("-Oz --strip-debug"). Each
    argument is its own item in the list.
  - Expecting RunAsync to throw on failure. It returns the exit code; check
    Succeeded. ShrinkAsync is the one that throws.
  - A module that uses a WebAssembly feature the optimizer has not been told
    about fails validation. Add the matching --enable-... switch through
    AdditionalArguments.
  - Removing debug information (the default) also removes function names. Set
    KeepDebugInfo = true when readable browser stack traces matter.
  - A read-only application folder on Linux or macOS: the first call must be
    able to give the program the execute permission. Build into a writable
    folder, or set the permission yourself (chmod +x).
  - Publishing the build program as a single file: the wasm-opt folder still
    has to sit beside the published program.
  - An installed wasm-opt elsewhere on PATH is a different copy. Put this
    package's folder FIRST (PrependToPath does) so it is the one used.


WHAT THIS PACKAGE DOES NOT DO
=============================
  - It does not compile anything to WebAssembly, and it does not produce the
    JavaScript glue a browser needs. It optimizes an existing file.
  - It does not compress files for HTTP (gzip, Brotli). That is the web
    server's job and is separate from shrinking.
  - It ships only wasm-opt, not the other programs of the project it comes
    from.
  - It does not install anything, change PATH, or touch environment variables.
  - It does not run in the browser or on the web server.
  - It does not support Linux on RISC-V, Windows on ARM64, musl-based Linux,
    Android or iOS as build machines.


WORKING EXAMPLES ON GITHUB
==========================
  Shrinking a file, levels, debug information, error handling:
    https://github.com/ellisnet/CodeBrix.WebPlatform.WasmShrink/blob/main/tests/CodeBrix.WebPlatform.WasmShrink.Tests/WasmShrinkToolTests.cs
  The command line built from WasmShrinkOptions:
    https://github.com/ellisnet/CodeBrix.WebPlatform.WasmShrink/blob/main/tests/CodeBrix.WebPlatform.WasmShrink.Tests/ArgumentBuilderTests.cs
  Platform detection and where the program is looked for:
    https://github.com/ellisnet/CodeBrix.WebPlatform.WasmShrink/blob/main/tests/CodeBrix.WebPlatform.WasmShrink.Tests/ToolLocatorTests.cs


QUICK REFERENCE CARD
====================
    using CodeBrix.WebPlatform.WasmShrink;

    WasmShrinkTool.IsAvailable                       bool, never throws
    WasmShrinkTool.CurrentRuntimeIdentifier          "linux-x64", ...
    WasmShrinkTool.GetExecutablePath()               full path, made runnable
    WasmShrinkTool.GetToolDirectory()                folder for PATH
    WasmShrinkTool.GetToolDirectory("linux-x64")     another platform's folder
    WasmShrinkTool.PrependToPath()                   PATH value, tool first
    await WasmShrinkTool.GetVersionAsync()           version line
    await WasmShrinkTool.RunAsync(args)              -> WasmShrinkResult (no throw on exit code)
    await WasmShrinkTool.ShrinkAsync(in, out)        smallest file, debug info removed (throws)
    await WasmShrinkTool.ShrinkAsync(in, out, new WasmShrinkOptions
    {
        Level = WasmShrinkLevel.Oz,                  O0 O1 O2 O3 O4 Os Oz
        KeepDebugInfo = false,
    })

    Errors: WasmShrinkException (platform, missing program, failure),
            FileNotFoundException (input), ArgumentException (empty path)

================================================================================

# CodeBrix.WebPlatform.WasmShrink

The WebAssembly size optimizer for the CodeBrix.WebPlatform web application platform. The package carries the `wasm-opt` program for every supported build platform, together with a small .NET library that finds the copy for the current machine, makes it runnable, and runs it - so a build shrinks the WebAssembly it produces without anything being installed. CodeBrix.WebPlatform.WasmShrink is provided as a .NET 10 library and associated `CodeBrix.WebPlatform.WasmShrink.ApacheLicenseForever` NuGet package.

CodeBrix.WebPlatform.WasmShrink supports applications and assemblies that target Microsoft .NET version 10.0 and later.
Microsoft .NET version 10.0 is a Long-Term Supported (LTS) version of .NET, and was released on Nov 11, 2025; and will be actively supported by Microsoft until Nov 14, 2028.
Please update your C#/.NET code and projects to the latest LTS version of Microsoft .NET.

## Installation

```
dotnet add package CodeBrix.WebPlatform.WasmShrink.ApacheLicenseForever
```

Note that the NuGet package ID and the namespace are different - there is no package named plain `CodeBrix.WebPlatform.WasmShrink`:

* NuGet package ID: `CodeBrix.WebPlatform.WasmShrink.ApacheLicenseForever`
* Assembly and primary namespace: `CodeBrix.WebPlatform.WasmShrink` - i.e. `using CodeBrix.WebPlatform.WasmShrink;`

XML documentation (IntelliSense) ships alongside the assembly.

CodeBrix.WebPlatform.WasmShrink has no dependencies other than .NET.

## CodeBrix.WebPlatform.WasmShrink supports:

* Shrinking a WebAssembly file with one call, choosing between the smallest file and the fastest code
* Keeping or removing debug information, so a development build can still show readable failures
* Running the optimizer with any arguments of your own and reading its exit code and output
* Handing another build tool the optimizer: a folder holding only that program, ready to be placed on `PATH`
* The build platforms of CodeBrix.WebPlatform: Linux x64 and ARM64, Windows x64, macOS on Apple Silicon and Intel
* Nothing to install: the program arrives with the package and is copied beside the application that references it
* No Node.js: nothing here uses, needs or talks to it

## Requirements

The package is used by the program that builds an application, on the machine that builds it. It is not part of the built web application and is not needed where that application runs.

On Linux the optimizer needs the GNU C library, as found on Debian-based distributions; distributions built on a different C library are not supported.

## Sample Code

### Shrink a WebAssembly file

```csharp
using CodeBrix.WebPlatform.WasmShrink;

await WasmShrinkTool.ShrinkAsync("app.wasm", "app.wasm");
```

### Choose what to optimize for

```csharp
using CodeBrix.WebPlatform.WasmShrink;

var options = new WasmShrinkOptions
{
    Level = WasmShrinkLevel.O3,   // fastest code; the default, Oz, gives the smallest file
    KeepDebugInfo = true,         // keep function names for readable failures
};
options.AdditionalArguments.Add("--enable-bulk-memory");

await WasmShrinkTool.ShrinkAsync("app.wasm", "app.min.wasm", options);
```

### Let another build tool find the optimizer

```csharp
using System.Diagnostics;
using CodeBrix.WebPlatform.WasmShrink;

var startInfo = new ProcessStartInfo("my-build-tool");
startInfo.Environment["PATH"] = WasmShrinkTool.PrependToPath();
```

### Run it with your own arguments

```csharp
using CodeBrix.WebPlatform.WasmShrink;

WasmShrinkResult result = await WasmShrinkTool.RunAsync(new[] { "app.wasm", "--print" });
if (!result.Succeeded)
{
    Console.Error.WriteLine(result.StandardError);
}
```

## Documentation

The NuGet package includes `AGENT-README.txt`, a complete API reference and usage guide written for AI coding agents - point your agent at that file when it is writing code against this library.

Additional sample code and usage examples are available in the `CodeBrix.WebPlatform.WasmShrink.Tests` project:
https://github.com/ellisnet/CodeBrix.WebPlatform.WasmShrink/tree/main/tests/CodeBrix.WebPlatform.WasmShrink.Tests

## License

CodeBrix.WebPlatform.WasmShrink is licensed under the Apache License 2.0 - see the
[LICENSE](https://github.com/ellisnet/CodeBrix.WebPlatform.WasmShrink/blob/main/LICENSE) file.

For licensing and provenance information about the open source code included in
this package, see [THIRD-PARTY-NOTICES.txt](https://github.com/ellisnet/CodeBrix.WebPlatform.WasmShrink/blob/main/THIRD-PARTY-NOTICES.txt).

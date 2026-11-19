================================================================================
MAINTAINER-README: CodeBrix.WebPlatform.WasmShrink
Notes for people and agents MAINTAINING this repository - not for package
consumers
================================================================================

If you are CONSUMING the NuGet package, stop reading and open AGENT-README.txt
instead. Everything below is about the repository itself: how it is laid out,
how it builds, how it is tested, how it is packaged, and the conventions the
source follows.


PURPOSE AND SCOPE
=================
    PackageId:  CodeBrix.WebPlatform.WasmShrink.ApacheLicenseForever
    Assembly:   CodeBrix.WebPlatform.WasmShrink
    Project:    src/CodeBrix.WebPlatform.WasmShrink/
                CodeBrix.WebPlatform.WasmShrink.csproj
    License:    Apache-2.0
    Consumer documentation: AGENT-README.txt (repo root)

The package gives a CodeBrix.WebPlatform build the wasm-opt WebAssembly
optimizer with nothing installed on the machine. It holds the wasm-opt program
for each supported build platform and a small .NET library that finds, prepares
and runs the copy for the current machine.

It belongs to the CodeBrix.WebPlatform family (repository CodeBrix.WebPlatform)
and exists so that the platform's frontend-building library can declare a
dependency on it. It lives in a repository of its own because it carries a
large vendored C++ source tree and native binaries.

RULES THAT HOLD HERE
  - NO NODE.JS. Nothing this repository ships uses, relies on or talks to
    Node.js. The upstream project's JavaScript build and its JavaScript-based
    tests are never built or run.
  - THE LIBRARY HAS NO NUGET DEPENDENCIES and knows nothing about any tool
    that might consume it. Which arguments a build tool passes to wasm-opt is
    that tool's business.
  - THE NATIVE BUILD NEVER REACHES OUTSIDE THE REPOSITORY. The source is
    vendored; the build runs with the network off. Only tools installed on the
    build machine are external (see tools/binaryen-native-tools).
  - Nothing new (NuGet package, vendored code, assembly) without the
    repository owner's approval by name. Stable releases only.

SUPPORTED BUILD PLATFORMS
    linux-x64   linux-arm64   win-x64   osx-arm64   osx-x64

These are the platforms on which a CodeBrix.WebPlatform application can be
built. Linux on RISC-V and Windows on ARM64 are deliberately absent: the
platform also requires the standalone Tailwind program, which is not published
for either. Do not add binaries or scripts for them unless the owner asks.


REPOSITORY LAYOUT
=================
    src/CodeBrix.WebPlatform.WasmShrink/         the library (packable)
      WasmShrinkTool.cs                          the public entry point
      WasmShrinkOptions.cs, WasmShrinkLevel.cs,
      WasmShrinkResult.cs, WasmShrinkException.cs
      Internal/                                  ToolLocator, ArgumentBuilder,
                                                 ProcessRunner
      InternalsVisibleTo.cs
      buildTransitive/                           the .targets file packed into
                                                 the package (see PACKAGING)
    tests/CodeBrix.WebPlatform.WasmShrink.Tests/ xUnit v3 tests
    native_libraries/<rid>/                      the committed wasm-opt programs,
                                                 licence texts and build records
    tools/binaryen-native-tools/                 vendored source + build tooling
    CodeBrix.WebPlatform.WasmShrink.slnx         the solution

Root files: the solution's "Solution Items" folder lists .gitignore,
AGENT-README.txt, EXTRAS-README.txt, global.json, icon-codebrix-128.png,
LICENSE, MAINTAINER-README.txt, README-INDEX.txt, README.md and
THIRD-PARTY-NOTICES.txt. Beside them are the eight AI-assistant pointer files
(byte-for-byte copies of the family's canonical set; never edited here) and
.gitattributes.

global.json pins the .NET SDK (10.0.404, rolling forward to the latest feature
band, no prereleases) and selects the Microsoft.Testing.Platform test runner.
It is the family's standard file for repositories with no Android projects.

.gitattributes keeps every text file LF on every platform, declares the
binaries, and switches line-ending handling OFF inside the vendored source
tree so that it stays byte-for-byte what upstream published.

.gitignore is the standard Visual Studio template with a short section at the
end. Its last lines un-ignore the vendored source tree and native_libraries/;
they must stay last, because the template above them would otherwise hide
files inside those folders (folders named Debug or Release, *.log, *.obj ...).


BUILDING
========
    dotnet build --configuration Release CodeBrix.WebPlatform.WasmShrink.slnx

0 warnings / 0 errors is the bar. GenerateDocumentationFile is on, so CS1591
is fixed by writing the doc comment, never by NoWarn.

Building the solution does NOT build wasm-opt. The programs under
native_libraries/ are built separately, once per upgrade, with the scripts in
tools/binaryen-native-tools (see THE NATIVE PROGRAMS below).


TESTING
=======
xUnit v3 with SilverAssertions. The test runner is Microsoft.Testing.Platform,
selected by global.json (do not delete it - without it `dotnet test` falls
back to the VSTest bridge, which fails on the .NET 10 SDK).

    dotnet test --solution CodeBrix.WebPlatform.WasmShrink.slnx

If that reports zero tests, run the test assembly directly and quote its
counts:

    dotnet tests/CodeBrix.WebPlatform.WasmShrink.Tests/bin/Debug/net10.0/CodeBrix.WebPlatform.WasmShrink.Tests.dll

No coverage collector is referenced.

Two kinds of test:
  - Unit tests of the internals (ToolLocator, ArgumentBuilder) and the small
    public types. They run everywhere.
  - WasmShrinkToolTests runs the REAL wasm-opt for the current machine, taken
    from native_libraries/ through the project reference. On a platform whose
    program has not been built yet these tests report as SKIPPED, with the
    reason; they are not failures. Once that platform's program is committed
    they run by themselves.

The module the tests shrink is a few lines of WebAssembly text written for
this repository (a constant in WasmShrinkToolTests). There is no third-party
test data.

WasmShrinkToolTests pins the version line the bundled programs print
(BundledVersionLine). Change it together with the programs.


THE NATIVE PROGRAMS
===================
Everything about building wasm-opt is in tools/binaryen-native-tools; start at
its README.txt. In short:

  tools/binaryen-native-tools/binaryen/   the upstream source (its .github/
                                          folder removed - this repository
                                          carries no workflow files), never
                                          patched, never written to by a build
  tools/binaryen-native-tools/UPSTREAM.txt
                                          how the copy was made and how to
                                          verify it (mechanics only; the legal
                                          facts are in THIRD-PARTY-NOTICES.txt)
  tools/binaryen-native-tools/BUILD-PROVENANCE.txt
                                          the record of each platform's build
  tools/binaryen-native-tools/linux/      container definitions and scripts;
                                          builds linux-x64 and linux-arm64 on
                                          one machine (arm64 under emulation)
  tools/binaryen-native-tools/windows/    script for win-x64
  tools/binaryen-native-tools/macos/      script for osx-arm64 and osx-x64
  native_libraries/<rid>/                 the finished program, a
                                          .provenance.txt record, and the
                                          licence texts of what is compiled in

The Linux programs are built in fixed, digest-pinned container images so that
they run on older distributions too, with the C++ runtime linked in; they need
only the GNU C library at run time.

A platform with no folder under native_libraries/ has not been built yet. The
package still builds and packs without it; WasmShrinkTool reports that
platform's program as not found.


PACKAGING / PUBLISHING
======================
The version is the family's date-stamped block in the csproj
(1.<years since 2026>.<day of year>.<minute of day>, UTC); every build
produces a new version and a new .nupkg under
src/CodeBrix.WebPlatform.WasmShrink/bin/<Configuration>/.

What the .nupkg contains:
  lib/net10.0/                      the assembly and its XML documentation
  tools/wasm-opt/<rid>/             the program and LICENSE-*.txt for each
                                    platform that has been built
  buildTransitive/CodeBrix.WebPlatform.WasmShrink.ApacheLicenseForever.targets
  icon-codebrix-128.png, README.md, AGENT-README.txt, THIRD-PARTY-NOTICES.txt

WHY NOT runtimes/<rid>/native. That convention is for libraries a process
loads. NuGet mixes every package's files for a platform into one folder and
flattens them into the application folder for a platform-specific build. A
program that is put on PATH needs a folder of its own at a fixed place. So the
programs are packed under tools/wasm-opt/ and the .targets file copies that
tree into the consuming project's output folder as wasm-opt/<rid>/. It is
under buildTransitive/ so the copy also happens in a project that receives
this package through another package. The file's name must stay equal to the
PackageId or NuGet ignores it.

For a PROJECT reference (the tests) the same copy is done by the None items
in the library's csproj. Keep the two in step: both produce
<output>/wasm-opt/<rid>/<files>, which is where ToolLocator looks.

The *.provenance.txt files beside the programs are excluded from the package.

The execute permission does not survive a NuGet package. ToolLocator restores
it on first use; nothing in packaging needs to.

After changing native_libraries/ or the packaging, unzip the .nupkg and check
its contents, and check its size. The owner's bar: if the package for all
platforms would exceed 100 MB, stop and raise it - the fallback is one package
per platform with the same library API.

Do not publish from here. The repository owner publishes. The package is not
to be published until all five platforms' programs are in it, unless the owner
says otherwise.


UPGRADING THE VENDORED SOURCE
=============================
 1. Replace tools/binaryen-native-tools/binaryen/ with the new upstream
    release, remove its .github/ folder again, and update UPSTREAM.txt (see
    that file for the exact steps).
 2. Rebuild every platform's program with the scripts; each writes its record.
 3. Update BundledVersionLine in WasmShrinkToolTests.
 4. Re-read the upstream licence files and update THIRD-PARTY-NOTICES.txt and
    the LICENSE-*.txt files if anything bundled changed.
 5. Build, test, unzip the package and check it.
 6. Rebuild an application that uses the package and check that it still
    works in a browser: a newer optimizer can change the output.


CODING CONVENTIONS
==================
The family conventions:
  - every .cs file: usings at the top (System first, alphabetical on the
    namespace name), one blank line, a file-scoped namespace, one blank line,
    the type; no leading blank line; no banner comments on new files;
  - no nullable-reference annotations (`?` on reference types), no `!`, no
    `#nullable`, no global usings, no implicit usings;
  - XML doc comments on every public member;
  - no warning suppression in project files;
  - tests: files named <Class>Tests.cs; methods Member_does_something or
    plain snake_case; //Arrange //Act //Assert in multi-statement bodies,
    expression bodies for single statements; SilverAssertions fluent form;
    TestContext.Current.CancellationToken passed to cancellable calls.

Wording: never the word for the brand of interlocking toy bricks; no weapon
metaphors.


PROVENANCE / VENDORED SOURCES
=============================
The library's own source is written for this project. The wasm-opt programs
are built from the vendored Binaryen source. What came from where, and under
which licences, is in THIRD-PARTY-NOTICES.txt; how the copy was made is in
tools/binaryen-native-tools/UPSTREAM.txt.


NOTES
=====
  - The library deliberately does not run wasm-opt from the NuGet package
    folder. It looks beside the running application only, so an application
    behaves the same whatever the machine's package cache holds.
  - A tool that looks wasm-opt up on PATH may also look in a private install
    folder of its own first. That is the consuming tool's concern, handled
    where that tool is driven, not here.
  - Not done: this repository is not yet in the family's repository list or
    its document collector.

================================================================================

================================================================================
EXTRAS-README: CodeBrix.WebPlatform.WasmShrink
Samples, tools and other content in this repository that is not part of a NuGet
package
================================================================================

This repository ships no sample applications or demos. Exactly one project is
packable - src/CodeBrix.WebPlatform.WasmShrink - and everything listed below
exists to build, test or document it.

For runnable, compilable usage of the library, read the test project: the
"WORKING EXAMPLES ON GITHUB" section of AGENT-README.txt maps each feature area
to the test file that exercises it.


TEST PROJECT
============
    tests/CodeBrix.WebPlatform.WasmShrink.Tests/

The only non-package project in the solution. xUnit v3; run it as described in
MAINTAINER-README.txt (TESTING). It is not included in the package.


THE NATIVE BUILD TOOLING
========================
    tools/binaryen-native-tools/

Everything needed to rebuild the wasm-opt programs from this repository alone:
the complete vendored source, the build scripts and container definitions for
each platform, and the build records. Start at
tools/binaryen-native-tools/README.txt. None of this folder is included in the
package.


THE BUILT PROGRAMS
==================
    native_libraries/<rid>/

The finished wasm-opt programs, committed. The program and the licence texts
beside it ARE included in the package (see PACKAGING / PUBLISHING in
MAINTAINER-README.txt); the *.provenance.txt build records beside them are
not.

================================================================================

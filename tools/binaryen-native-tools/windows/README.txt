================================================================================
tools/binaryen-native-tools/windows - building wasm-opt.exe for win-x64
================================================================================

>>> STATUS 2026-11-19: FIRST RUN DONE. build.wasm-opt.ps1 (written on Linux on
    2026-11-18) ran UNCHANGED on Jeremy's x64 Windows 11 machine with Visual
    Studio Professional 2026 18.12.1 (cl 19.52.37029), cmake 4.4.3 and ninja
    1.13.2, and passed the whole gate, the functional gate included. The
    result is adopted into ../../../native_libraries/win-x64/ and recorded in
    ../BUILD-PROVENANCE.txt; the managed suite passed against it.

    One thing the run needed outside the script: C:\Strawberry\c\bin (Strawberry
    Perl's MinGW folder, with its own older cmake 3.29.2, ninja 1.12.0 and
    nasm) was taken OFF THE PATH for the build, so the cmake and ninja above
    were the ones found. If Strawberry Perl is installed, do the same. <<<

WHAT THIS IS
--------------------------------------------------------------------------------
One script, build.wasm-opt.ps1. It builds wasm-opt.exe from ../binaryen - the
vendored, unmodified snapshot - with MSVC through CMake's Ninja generator,
gates the result (including running it), and writes ../output/win-x64/. It
downloads nothing and installs nothing. x64 only: win-arm64 is not a
CodeBrix.WebPlatform.WasmShrink RID.

PREREQUISITES (checked, never installed)
--------------------------------------------------------------------------------
  * Windows 10/11, x64 (an ARM64 Windows machine also works: it builds the
    x64 binary with the arm64_amd64 cross tools and runs it under emulation).
  * Visual Studio 2022 or newer, or its Build Tools, with the workload
    "Desktop development with C++" (MSVC with C++20 support - 17.x is new
    enough; binaryen's own CI uses windows-latest):
      winget install Microsoft.VisualStudio.2022.BuildTools
    (then add the workload in the Visual Studio Installer). vswhere.exe, which
    every Visual Studio installs, is how the script finds it; vcvarsall.bat
    supplies cl.exe, link.exe and dumpbin.exe.
  * CMake 3.16.3 or newer and Ninja on PATH after vcvarsall - the Visual Studio
    component "C++ CMake tools for Windows" provides both; or:
      winget install Kitware.CMake
      winget install Ninja-build.Ninja
  * PowerShell 5.1 (built in) or 7.

USAGE
--------------------------------------------------------------------------------
    cd tools\binaryen-native-tools\windows
    .\build.wasm-opt.ps1
    .\build.wasm-opt.ps1 -BuildRoot D:\cbx-wasm-opt

  -BuildRoot (default C:\cbx-wasm-opt) is where the source copy and the build
  tree live. Keep it a short path OUTSIDE your user profile: MSVC has no
  equivalent of -ffile-prefix-map, binaryen keeps assert() on, and assert()
  embeds each source file's path - so the build root's path ends up inside
  wasm-opt.exe. The gate fails if the user-profile path or the repository path
  is found in the binary.

THE BUILD
--------------------------------------------------------------------------------
    cmake -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl
          -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
          <BINARYEN_CMAKE_OPTIONS from ..\linux\pins.env>
    cmake --build . --target wasm-opt

  * the static CRT (/MT) means no Visual C++ Redistributable is needed.
    binaryen's CMakeLists.txt already selects MultiThreaded for every non-Debug
    MSVC build; the script states it rather than relying on that;
  * binaryen forces BUILD_SHARED_LIBS OFF under MSVC anyway, so libbinaryen is
    static here as on Linux;
  * binaryen's own MSVC flags apply: /O2, /UNDEBUG (assertions on), /MP is
    harmless under Ninja, and the linker gets /STACK:8388608 (8 MB);
  * CMake's Release configuration links without /DEBUG, so no .pdb is made;
  * upstream's own Windows release job uses CMake's default Visual Studio
    generator; Ninja here gives the same compiler and flags with a simpler
    output layout (bin\wasm-opt.exe).

THE GATE
--------------------------------------------------------------------------------
  1. PE machine 0x8664 (x64).
  2. Imports - operating-system DLLs only (the allow-list is in the script);
     any VCRUNTIME*, MSVCP*, ucrtbase or api-ms-win-crt-* import fails it (the
     static CRT did not take).
  3. No user-profile or repository path in the binary (see -BuildRoot).
  4. Configure - binaryen printed "statically linked library",
     /DBUILD_LLVM_DWARF and /UNDEBUG.
  5. Functional - the same checks as ../linux/functional-gate.sh, in
     PowerShell, against ../linux/gate-fixture.wat with the CONSUMER_* flag
     sets and EXPECTED_RESULTS from ../linux/pins.env (README of linux/,
     THE VERIFICATION GATE, item 8).

  The build-root path WILL appear in the binary (as assert() file names); that
  is recorded in BUILD-INFO.txt, not a failure.

OUTPUT (../output/win-x64/)
--------------------------------------------------------------------------------
  wasm-opt.exe, the LICENSE-*.txt files named in ../linux/pins.env
  (LICENCE_FILES), BUILD-INFO.txt, SHA256SUMS.txt, gate-run\ (fixture outputs
  and logs).

  The gzip size in BUILD-INFO.txt comes from .NET's GZipStream and is NOT
  comparable with `gzip -9` on Linux; measure the shipped file with gzip -9 on
  Linux for the record in ../BUILD-PROVENANCE.txt.

  Third-party evidence: the Linux build's third-party-evidence.txt is the
  record of which bundled pieces are compiled in. MSVC links the same object
  files from the same CMake targets, so the licence list is the same; if a
  future binaryen changes the targets, add /MAP to the link and check.

ADOPTING A BUILT EXE
--------------------------------------------------------------------------------
  1. Read BUILD-INFO.txt.
  2. Copy wasm-opt.exe and the LICENSE-*.txt files to
     ..\..\..\native_libraries\win-x64\.
  3. Write native_libraries\win-x64\wasm-opt.exe.provenance.txt from
     BUILD-INFO.txt (model it on ..\..\..\native_libraries\linux-x64\
     wasm-opt.provenance.txt).
  4. Replace the win-x64 PENDING section in ..\BUILD-PROVENANCE.txt.
  5. Run the managed test suite on Windows before publishing.
================================================================================

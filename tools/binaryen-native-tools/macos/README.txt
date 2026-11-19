================================================================================
tools/binaryen-native-tools/macos - building wasm-opt for osx-arm64 and
                                    osx-x64
================================================================================

>>> STATUS 2026-11-18: build.sh is WRITTEN BUT NEVER RUN - it was written on
    Linux, which has no Apple SDK. There are NO osx-* binaries in
    ../../../native_libraries/ yet; ../BUILD-PROVENANCE.txt lists osx-arm64
    and osx-x64 as PENDING. Expect to fix something on the first real run; fix
    it in the script, record it in ../BUILD-PROVENANCE.txt, and rewrite this
    block. <<<

WHAT THIS IS
--------------------------------------------------------------------------------
build.sh builds wasm-opt from ../binaryen - the vendored, unmodified snapshot -
with Apple clang, for each slice separately (thin executables, not one
universal file), checks the result and writes ../output/osx-<arch>/. Both
slices are meant to be built on ONE Apple Silicon Mac, as upstream's own macOS
release job does (macos-14, CMAKE_OSX_ARCHITECTURES). It downloads nothing and
installs nothing.

PREREQUISITES (checked, never installed)
--------------------------------------------------------------------------------
  * macOS on Apple Silicon (an Intel Mac builds both slices too, but can run
    only osx-x64).
  * Xcode or the Command Line Tools (clang with C++20, the macOS SDK, otool,
    lipo, strip, codesign):      xcode-select --install
  * CMake 3.16.3 or newer and Ninja on PATH:      brew install cmake ninja
  * Optional, to RUN the osx-x64 slice on Apple Silicon (the functional gate):
      softwareupdate --install-rosetta

USAGE
--------------------------------------------------------------------------------
    cd tools/binaryen-native-tools/macos
    ./build.sh               # both slices
    ./build.sh arm64         # osx-arm64 only
    ./build.sh x64           # osx-x64 only

THE BUILD
--------------------------------------------------------------------------------
    cmake -G Ninja <BINARYEN_CMAKE_OPTIONS from ../linux/pins.env>
          -DCMAKE_OSX_ARCHITECTURES=arm64|x86_64
          -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0|10.15
          -DCMAKE_C_FLAGS / CMAKE_CXX_FLAGS = -ffile-prefix-map=...
    cmake --build . --target wasm-opt
    strip wasm-opt; codesign --force --sign - wasm-opt

  * the C++ runtime is the SYSTEM libc++ (/usr/lib/libc++.1.dylib), present on
    every macOS; libbinaryen is static (BUILD_SHARED_LIBS=OFF), so the
    executable links only libc++ and libSystem;
  * deployment targets: 11.0 for arm64 (the first macOS on Apple Silicon),
    10.15 for x86_64 (binaryen's own CMakeLists default) - the floors
    upstream's own macOS binaries get. Override with DEPLOYMENT_TARGET_ARM64 /
    DEPLOYMENT_TARGET_X64; if the compiler rejects a C++20 library feature as
    unavailable on that macOS, raise the floor and record it;
  * `strip` removes the symbol table (upstream's release uses `strip -x`, which
    keeps global symbols; an executable needs neither); stripping invalidates
    the linker's ad-hoc signature, so the file is signed again, ad hoc
    (codesign --sign -). arm64 macOS refuses to run unsigned code; an ad-hoc
    signature is not a Developer ID, so a consuming app that is notarised
    signs this file again with its own identity.

THE GATE
--------------------------------------------------------------------------------
  1. lipo -archs is exactly the requested slice (thin).
  2. Links only /usr/lib/libc++.1.dylib and /usr/lib/libSystem.B.dylib; no
     LC_RPATH.
  3. LC_BUILD_VERSION minos equals the requested deployment target.
  4. codesign --verify --strict passes.
  5. No build paths (scratch, build, the tools folder, $HOME) in the binary.
  6. Configure - binaryen printed "statically linked library",
     -DBUILD_LLVM_DWARF and -UNDEBUG.
  7. Functional - ../linux/functional-gate.sh, the same script as on Linux,
     where the Mac can run the slice (natively, or osx-x64 under Rosetta 2).
     A slice the Mac cannot run is reported as [skip], and must then be run
     on a Mac that can before it is adopted.

OUTPUT (../output/osx-<arch>/)
--------------------------------------------------------------------------------
  wasm-opt, the LICENSE-*.txt files named in ../linux/pins.env
  (LICENCE_FILES), BUILD-INFO.txt, GATE.txt, SHA256SUMS.txt, gate-run/.

  Third-party evidence: the Linux build's third-party-evidence.txt is the
  record of which bundled pieces are compiled in. Apple's linker links the same
  object files from the same CMake targets, so the licence list is the same;
  if a future binaryen changes the targets, link with -Wl,-map,<file> and
  check.

ADOPTING A BUILT EXECUTABLE
--------------------------------------------------------------------------------
  1. Read BUILD-INFO.txt (minos above all).
  2. Copy wasm-opt and the LICENSE-*.txt files to
     ../../../native_libraries/osx-<arch>/.
  3. Write native_libraries/osx-<arch>/wasm-opt.provenance.txt from
     BUILD-INFO.txt (model it on ../../../native_libraries/linux-x64/
     wasm-opt.provenance.txt).
  4. Replace that RID's PENDING section in ../BUILD-PROVENANCE.txt.
  5. Run the managed test suite on a Mac before publishing.
================================================================================

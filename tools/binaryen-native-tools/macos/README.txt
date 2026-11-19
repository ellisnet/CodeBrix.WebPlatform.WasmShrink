================================================================================
tools/binaryen-native-tools/macos - building wasm-opt for osx-arm64 and
                                    osx-x64
================================================================================

>>> STATUS 2026-11-19: build.sh was written on Linux (2026-11-18) and FIRST
    RUN on 2026-11-19 on Jeremy's Mac mini (Apple M2 Pro, macOS 27.2.1, Xcode
    27.2). Both slices were built, passed every gate check (osx-x64's
    functional gate under Rosetta 2), were built a second time
    byte-identically, and were adopted into ../../../native_libraries/
    osx-<arch>/. The managed tests (77, 0 failed, 0 skipped) ran the arm64
    file. The first run found one bug, fixed in the script and recorded in
    ../BUILD-PROVENANCE.txt: scratch paths ended up in the executable, and
    the build-path gate missed them ($TMPDIR's trailing "/"). Decided before
    the run: the x86_64 floor is 11.0, not 10.15 (THE BUILD), and the
    pre-strip executable is kept, uncommitted (OUTPUT). <<<

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
          -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0          (both slices)
          -DCMAKE_C_FLAGS / CMAKE_CXX_FLAGS = -ffile-prefix-map=...
    cmake --build . --target wasm-opt
    cp wasm-opt unstripped/wasm-opt        (the pre-strip copy; see OUTPUT)
    strip wasm-opt; codesign --force --sign - wasm-opt

  * the C++ runtime is the SYSTEM libc++ (/usr/lib/libc++.1.dylib), present on
    every macOS; libbinaryen is static (BUILD_SHARED_LIBS=OFF), so the
    executable links only libc++ and libSystem;
  * deployment targets: 11.0 for BOTH slices. For arm64 that is the first
    macOS on Apple Silicon - the floor upstream's own arm64 binary gets. For
    x86_64 it is RAISED from 10.15 (binaryen's own CMakeLists default, which
    upstream's x86_64 binary keeps), by the owner's decision of 2026-11-18:
    the libc++ headers of current Xcode (27.2) support macOS 11.0 and newer
    only, and at 10.15 every C++ file warns "The selected platform is no
    longer supported by libc++." Override with DEPLOYMENT_TARGET_ARM64 /
    DEPLOYMENT_TARGET_X64, and record any change in ../BUILD-PROVENANCE.txt;
  * the -ffile-prefix-map options keep the scratch folder out of the binary
    (binaryen keeps assert() on, which embeds __FILE__). macOS's $TMPDIR ends
    in "/"; the script drops it before building the scratch path, because
    CMake collapses "//" and a prefix map spelled with "//" never matches -
    the first run, 2026-11-19, shipped 107 scratch paths that way until this
    was fixed;
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
  5. No build paths (the scratch root, scratch, build, the tools folder,
     $HOME, /var/folders/) in the binary.
  6. Configure - binaryen printed "statically linked library",
     -DBUILD_LLVM_DWARF and -UNDEBUG.
  7. Functional - ../linux/functional-gate.sh, the same script as on Linux,
     where the Mac can run the slice (natively, or osx-x64 under Rosetta 2).
     A slice the Mac cannot run is reported as [skip], and must then be run
     on a Mac that can before it is adopted.

OUTPUT (../output/osx-<arch>/)
--------------------------------------------------------------------------------
  wasm-opt, the LICENSE-*.txt files named in ../linux/pins.env
  (LICENCE_FILES), BUILD-INFO.txt, GATE.txt, SHA256SUMS.txt, gate-run/, and
  unstripped/wasm-opt - the executable as linked, before `strip` (the symbol
  table; no DWARF, as there is no -g). Same LC_UUID as the shipped file. It
  is NOT committed (the owner's decision, 2026-11-18): adoption copies it to
  ../unstripped/osx-<arch>/, which is git-ignored, so it stays on the build
  Mac - see ../unstripped/README.txt.

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
  3. Copy unstripped/wasm-opt to ../unstripped/osx-<arch>/wasm-opt and
     rewrite ../unstripped/SHA256SUMS (git-ignored; never committed).
  4. Write native_libraries/osx-<arch>/wasm-opt.provenance.txt from
     BUILD-INFO.txt (the osx-arm64 one is the model).
  5. Replace that RID's section in ../BUILD-PROVENANCE.txt.
  6. Run the managed test suite on a Mac before publishing.
================================================================================

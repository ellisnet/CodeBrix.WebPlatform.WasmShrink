================================================================================
binaryen-native-tools - everything needed to build the wasm-opt executables
================================================================================

THE RULE THIS FOLDER EXISTS FOR
--------------------------------------------------------------------------------
Jeremy, 2026-09-15 (written for CodeBrix.Ollama's llama-native-tools, and the
rule every CodeBrix native-tools folder is held to):

    "Every single file we need, in order to build these native libraries,
    must be housed in that folder. We must not be pulling from external
    sources during the build process. If, a year from now, I need to redo
    these builds, for some reason - and other source code/repos are not
    available to me - I still need to be able to redo the build. The
    exception is the actual tools like cmake and ninja and those kinds of
    tools - I don't want to vendor a bunch of build tools into this folder.
    But all source code and header files, etc must be in the folder - the
    build process cannot pull from other repos, etc."

Everything below follows from that. The folder is modelled, file for file, on
CodeBrix.LibGit2's libgit2-native-tools/ (itself modelled on CodeBrix.Sdl3's
sdl3-native-tools/), which were built to the same rule. The native shipped
here is not a library but an executable - binaryen's wasm-opt, the WebAssembly
optimiser - which the package runs as a child process.


HOW THE RULE IS ENFORCED, NOT JUST STATED
--------------------------------------------------------------------------------
The Linux builds run inside a container started with `--network none`. The
first thing the build prints is the proof: the container has no network
interface but loopback. If any step ever tried to fetch a source file or a
dependency, it would fail there instead of quietly working on whichever
machine happened to have a connection. The Windows and macOS scripts fetch
nothing either.

binaryen's CMake has no download path: no FetchContent, no ExternalProject.
Its four git submodules (googletest, fuzztest, mimalloc, the spec test suite)
are absent from the vendored tree, and every option that would need one is off
(see UPSTREAM.txt and linux/pins.env).

The things that live outside the folder, by Jeremy's stated exception:
  * the tools installed on each build machine (cmake, ninja, the compilers, a
    container engine, Visual Studio, Xcode) - each platform README lists them,
    with the command that installs them; no script here installs anything;
  * on Linux, the digest-pinned manylinux container images that supply the
    compiler and the glibc floor, and the derived images built on them (cmake
    and ninja wheels and `file` - nothing else). Building a derived image is
    the one step that uses the network. linux/README.txt documents a
    bare-host route for the day the images are gone.


FOLDER MAP
--------------------------------------------------------------------------------
  README.txt              this document
  BUILD-PROVENANCE.txt    what was actually built, when, by what, with what
                          hashes and gate results - one section per runtime
                          identifier - and how the build differs from
                          upstream's own release build
  UPSTREAM.txt            where the vendored tree came from: tag, commit,
                          tarball checksum, the exact copy commands, the tree
                          checksum, what is absent, how to verify it
  LICENSE-Unicode.txt     the Unicode, Inc. notice of the UTF conversion code
                          (LLVM's ConvertUTF.cpp) compiled into wasm-opt,
                          verbatim from that file's header - LLVM's licence
                          does not carry it. Every build copies it beside its
                          binary
  .gitignore              re-includes this folder's contents from the root
                          .gitignore (which ignores names such as *.env and
                          *.log) and ignores output/. Its first rule is
                          load-bearing - read the comment before editing it

  binaryen/               THE VENDORED BINARYEN - the unmodified
                          version_133 source tarball (tag version_133, commit
                          fba5005a132d85d578be5bd010e0487ed8e2ce3e), 3,036
                          files, test/ included; upstream's .github/ folder
                          removed (UPSTREAM.txt), git submodules absent.
                          Apache-2.0. Never patched, never written to by a
                          build

  linux/                  linux-x64, linux-arm64
                          pins.env, build.sh, container-build.sh,
                          Containerfile.x86_64, Containerfile.aarch64,
                          functional-gate.sh and gate-fixture.wat (the
                          functional gate shared by every platform),
                          README.txt
  windows/                win-x64. build.wasm-opt.ps1 (MSVC + CMake + Ninja,
                          static CRT), README.txt. Written 2026-11-18, UNRUN
  macos/                  osx-arm64, osx-x64. build.sh (Apple clang, system
                          libc++, ad-hoc signature), README.txt. Written
                          2026-11-18, UNRUN

  output/                 build results (git-ignored). Disposable


WHICH README TO READ
--------------------------------------------------------------------------------
  Building on Linux    -> linux/README.txt
  Building on Windows  -> windows/README.txt
  Building on a Mac    -> macos/README.txt

Each one lists the tools to install on that machine, with the exact command,
and nothing else is needed.


THE FIVE RUNTIME IDENTIFIERS
--------------------------------------------------------------------------------
  RID            built by                            shipped file   status
  -------------  ----------------------------------  -------------  ---------
  linux-x64      linux/build.sh x64                  wasm-opt       BUILT
  linux-arm64    linux/build.sh arm64                wasm-opt       BUILT
  win-x64        windows/build.wasm-opt.ps1          wasm-opt.exe   PENDING
  osx-arm64      macos/build.sh arm64                wasm-opt       PENDING
  osx-x64        macos/build.sh x64                  wasm-opt       PENDING

BUILT = built here from binaryen/, gated and adopted into
../../native_libraries/<rid>/. PENDING = the script is written but has never
been run; the owner runs it on his own Windows machine and Mac.
BUILD-PROVENANCE.txt says, per RID, exactly what happened.

NOT SUPPORTED, and neither built nor scripted: linux-riscv64, win-arm64,
android-*.

The shipped executables live in ../../native_libraries/<rid>/, each with a
wasm-opt.provenance.txt (wasm-opt.exe.provenance.txt on Windows) beside it.

Every RID folder also gets one licence file per piece of code COMPILED INTO
wasm-opt - the evidence for each is written by every Linux build to
output/<rid>/third-party-evidence.txt (from the linker's map file):

  LICENSE-Binaryen.txt     binaryen/LICENSE (Apache-2.0)
  LICENSE-Llvm.txt         binaryen/third_party/llvm-project/include/llvm/
                           LICENSE.TXT (Apache-2.0 WITH LLVM-exception, and
                           the legacy University of Illinois/NCSA licence)
  LICENSE-LlvmSupport.txt  binaryen/third_party/llvm-project/include/llvm/
                           Support/LICENSE.TXT (the LLVM System Interface
                           Library's extra copyright line - Path.cpp, which
                           includes Unix/Path.inc, is linked)
  LICENSE-Unicode.txt      LICENSE-Unicode.txt in this folder (ConvertUTF.cpp
                           is linked)
  LICENSE-Fp16.txt         binaryen/third_party/FP16/LICENSE (MIT; the
                           header-only FP16 conversions are compiled into
                           literal.cpp, Precompute.cpp, binaryen-c.cpp and
                           wasm-opt.cpp)

The names are package-unique (the family's precedents are LICENSE-SDL3.txt,
LICENSE-Dav1d.txt, LICENSE-Libgit2.txt) because these files land in a
consuming application's OUTPUT FOLDER, where a file named plainly LICENSE
collides with any other package that ships one there.


THE VENDORED RELEASE
--------------------------------------------------------------------------------
  binaryen  version_133 = commit fba5005a132d85d578be5bd010e0487ed8e2ce3e,
            released 2026-09-21. `wasm-opt --version` reports
            "wasm-opt version 133".

UPSTREAM.txt explains it and records how to verify the snapshot.


LICENCES AND NOTICES
--------------------------------------------------------------------------------
../../THIRD-PARTY-NOTICES.txt, at the root of this repository, carries
binaryen's licence and the notices for everything else the repository
incorporates. Read it before changing what this folder vendors.


A ONE-MINUTE TOUR (on Linux)
--------------------------------------------------------------------------------
    cd linux
    ./build.sh x64              # about a minute and a half once the image exists
    cat ../output/linux-x64/BUILD-INFO.txt
    cd ../output && sha256sum -c SHA256SUMS
================================================================================

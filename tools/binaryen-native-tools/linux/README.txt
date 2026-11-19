================================================================================
tools/binaryen-native-tools/linux - building wasm-opt for linux-x64 and
                                    linux-arm64
================================================================================

>>> STATUS 2026-11-18: see ../BUILD-PROVENANCE.txt for which RIDs are built,
    gated and adopted, with their hashes. Written and first run on the x86_64
    LMDE 7 laptop with podman 5.4.2: linux-x64 natively, linux-arm64 under
    qemu-user emulation - the route CodeBrix.LibGit2's libgit2-native-tools
    took. Both passed the gate on their first run. <<<

WHAT THIS IS
--------------------------------------------------------------------------------
Everything needed to build the two Linux wasm-opt executables this package
ships, from the binaryen snapshot vendored in ../binaryen/. Each build is
verified - including actually running it - before it is allowed to be adopted.

The build reaches nothing outside this repository. It literally cannot: the
compile runs in a container started with `--network none`, and the first thing
container-build.sh prints is the proof that the container has no network
interface but loopback. The source it compiles and the fixture it optimises
are files in this repository.

NOTHING HERE INSTALLS ANYTHING ON YOUR MACHINE. Every script checks what it
needs, and if something is missing it names it, prints the command that
installs it, and stops. Installing is your decision.


================================================================================
PREREQUISITES  (the complete list - one package, two if emulating)
================================================================================
  1. A container engine - podman (preferred) or docker.

       sudo apt install podman

     Verify:       podman --version

  2. ONLY IF building linux-arm64 on an x86_64 machine: qemu user-mode
     emulation and its binfmt registrations.

       sudo apt install qemu-user-static binfmt-support

     Verify:       ls /proc/sys/fs/binfmt_misc | grep qemu-aarch64

  3. Disk: about 2 GB per architecture for the base image plus its derived
     image, and about 1 GB of build tree per run (inside the container's
     /tmp, discarded when it exits). Memory: the x64 build runs one compiler
     per CPU core; binaryen's larger C++20 files take several hundred MB each.

  NOT REQUIRED ON THE HOST, AND DELIBERATELY SO: cmake, ninja, gcc, any
  cross-compiler. They live inside the container images, at pinned versions,
  so the build does not vary with whatever the workstation happens to have
  installed this year.


================================================================================
THE IMAGES, AND WHY THEY ARE PINNED BY DIGEST
================================================================================
  RID           base image                           glibc ceiling  compiler
  ------------  -----------------------------------  -------------  ---------
  linux-x64     quay.io/pypa/manylinux_2_28_x86_64    2.28           GCC 14.2.1
  linux-arm64   quay.io/pypa/manylinux_2_28_aarch64   2.28           GCC 14.2.1

The compiler is the images' gcc-toolset-14 - GCC 14.2.1 20250110 (Red Hat
14.2.1-11). binaryen 133 requires C++20 (CMAKE_CXX_STANDARD 20, REQUIRED);
GCC 14 is comfortably new enough, and container-build.sh refuses a GCC older
than MIN_GCC_MAJOR in pins.env.

WHY A CONTAINER, EVEN ON A NATIVE MACHINE. glibc symbol versioning is
forward-only: a binary compiled against the glibc on a current desktop distro
refuses to start on anything older. The manylinux images are old userlands
with modern compilers, which is exactly the tool for this. The glibc number in
the image name IS the compatibility ceiling the gate enforces; the floor
actually referenced is lower (recorded in ../BUILD-PROVENANCE.txt).

WHY DIGESTS. pins.env records a dated tag AND a sha256 digest for each image,
and build.sh resolves the digest. A tag can be moved; a digest cannot. The two
digests are the same ones CodeBrix.LibGit2 (and CodeBrix.Sdl3,
CodeBrix.VideoPlayback.Dav1d, CodeBrix.Ollama, CodeBrix.Audio) pin, so every
CodeBrix Linux native comes from one base userland.

THE IMAGES ARE THE "INSTALLED TOOLS" EXCEPTION TO THE RULE. Pulling a base
image and building the derived image are the only things the Linux route
fetches from outside the repository - and they are a compiler and two build
tools, not binaryen source. For the day the images are gone, see THE BARE-HOST
ROUTE at the end of this file.


================================================================================
THE DERIVED IMAGE - THE "INSTALL THE TOOLS" STEP
================================================================================
Containerfile.<arch> adds to the base image, and nothing else:
  * cmake and ninja at the versions pinned in pins.env (pip wheels from the
    image's own CPython);
  * `file`, for the gate (binutils - readelf, nm, objdump, strings, strip -
    comes with the image's gcc toolset).

    Containerfile.x86_64    -> codebrix-binaryen-build-x86_64
    Containerfile.aarch64   -> codebrix-binaryen-build-aarch64

NO -devel PACKAGES. wasm-opt needs a C++20 compiler and its own source: the
bundled pieces (LLVM's DWARF code, FP16) are in ../binaryen/third_party, and
the static libstdc++.a and libgcc_eh.a that -static-libstdc++ -static-libgcc
link come with gcc-toolset-14 in the base image.

Each Containerfile ends by PROVING its toolchain: it prints the compiler,
linker, glibc, cmake and ninja versions, checks the gate tools are present,
and compiles a C++20 program with -static-libstdc++ -static-libgcc, checks it
needs neither libstdc++.so nor libgcc_s.so, and runs it.

To force an image rebuild:      FORCE_IMAGE_REBUILD=1 ./build.sh


================================================================================
USAGE
================================================================================
    cd tools/binaryen-native-tools/linux
    ./build.sh                  # both RIDs, x64 first
    ./build.sh x64              # or arm64

  Environment variables:
    CONTAINER_ENGINE=docker ./build.sh          force an engine
    FORCE_IMAGE_REBUILD=1 ./build.sh            rebuild the derived image first
    SKIP_HOST_CHECK=1 ./build.sh x64            do not run the result on the
                                                host (see THE HOST CHECK)

  Timings: recorded per RID in ../BUILD-PROVENANCE.txt (2026-11-18, 24-core
  x86_64 laptop). linux-x64 builds in about a minute and a half once the
  image exists. linux-arm64 under qemu-user emulation is far slower - about
  22 minutes, because binaryen is a large C++20 code base and every compiler
  process is emulated - and its first image build (dnf + pip under emulation)
  adds about 3 minutes more. On a native arm64 machine it is as quick as x64.

  DO NOT RUN TWO COPIES OF build.sh AT ONCE. Both rewrite ../output/SHA256SUMS
  at the end.

  Output, git-ignored:
    ../output/<rid>/wasm-opt                  stripped - the file the package
                                              ships
    ../output/<rid>/LICENSE-*.txt             the licences of everything
                                              compiled in (pins.env,
                                              LICENCE_FILES)
    ../output/<rid>/BUILD-INFO.txt            toolchain, pins, configure
                                              summary, sizes (stripped and
                                              gzip -9), sha256, build-id,
                                              NEEDED, glibc floor, the gate
    ../output/<rid>/GATE.txt                  the gate's lines, verbatim
    ../output/<rid>/gate-run/                 the fixture outputs and the
                                              wasm-opt logs of the gate
    ../output/<rid>/third-party-evidence.txt  what the linker put in: every
                                              archive member, per archive;
                                              every llvm-project object,
                                              LINKED or not; every object that
                                              included an FP16 header
    ../output/<rid>/cmake-configure.log       the whole configure log
    ../output/<rid>/HOST-CHECK.txt, host-run/ the host check (THE HOST CHECK)
    ../output/<rid>/SHA256SUMS.txt            that RID's shipped files
    ../output/SHA256SUMS                      every executable, one line each


================================================================================
THE BUILD, IN ONE PARAGRAPH
================================================================================
container-build.sh copies ../binaryen to scratch (there is no patch step) and
configures binaryen's own CMakeLists.txt with BINARYEN_CMAKE_OPTIONS from
pins.env:

    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF
    -DENABLE_WERROR=OFF -DBUILD_MIMALLOC=OFF -DBUILD_LLVM_DWARF=ON
    -DBYN_ENABLE_ASSERTIONS=ON -DCMAKE_SKIP_RPATH=ON

(pins.env gives the reason for each; BUILD_SHARED_LIBS=OFF is what makes
libbinaryen a static library linked into wasm-opt - binaryen 133 has no
BUILD_STATIC_LIB option), with the Ninja generator and these flags:

    C/C++     -ffile-prefix-map for the scratch source, build and /work paths
              (binaryen keeps assert() on, which embeds __FILE__)
    linker    -static-libstdc++ -static-libgcc   (glibc stays dynamic)
              -Wl,-z,stack-size=8388608          (upstream's Linux release
                                                  links the same 8 MB stack)
              -Wl,--build-id=sha1
              -Wl,-Map=<build>/wasm-opt.map      (evidence only)

No -g. CMake's own Release flags (-O3 -DNDEBUG) are used, and binaryen adds
-UNDEBUG (assertions on, its default), -fno-rtti, -fno-omit-frame-pointer and
-fPIC itself. ONLY the wasm-opt target is built (with the static libbinaryen.a
it links). The result is stripped with `strip --strip-all`; no unstripped copy
is kept. The linker map, ninja's dependency log and the configure log become
output/<rid>/third-party-evidence.txt and cmake-configure.log.

How this differs from upstream's own release build is in
../BUILD-PROVENANCE.txt, DIFFERENCES FROM UPSTREAM'S RELEASE BUILD.


================================================================================
WHAT IS COMPILED IN - AND SO WHICH LICENCES TRAVEL WITH THE BINARY
================================================================================
Read from every build's third-party-evidence.txt (the linker map is the
evidence; a source file in the tree that the linker never pulled in is not
"compiled in"):

  binaryen itself          src/ - libbinaryen.a members, plus wasm-opt.cpp
                           and src/tools/fuzzing/*.cpp linked directly.
                           src/support/suffix_tree*.cpp, which are LLVM-derived
                           and carry Apache-2.0 WITH LLVM-exception headers,
                           are LINKED.                      LICENSE-Binaryen.txt
                                                            (+ LICENSE-Llvm.txt)
  third_party/llvm-project a CMake OBJECT library (llvm_dwarf) merged into
                           libbinaryen.a: 60 of its 63 objects are LINKED
                           (Binary, ObjectFile, SymbolicFile are not), among
                           them Path.cpp (Unix/Path.inc - the LLVM System
                           Interface Library), ConvertUTF.cpp (Unicode, Inc.
                           notice) and MD5.cpp (public-domain notice, no
                           conditions).                     LICENSE-Llvm.txt
                                                            LICENSE-LlvmSupport.txt
                                                            LICENSE-Unicode.txt
  third_party/FP16         header-only; included by literal.cpp,
                           Precompute.cpp, binaryen-c.cpp and wasm-opt.cpp,
                           whose half-precision conversions it supplies.
                                                            LICENSE-Fp16.txt
  third_party/wabt         NOT compiled (no object includes it).
  GCC runtime              libstdc++.a, libgcc_eh.a, libgcc.a members linked
                           statically (-static-libstdc++ -static-libgcc), and
                           glibc's libc_nonshared.a (atexit, elf-init) as in
                           every glibc program. These come with the compiler,
                           not with binaryen; see ../../THIRD-PARTY-NOTICES.txt.


================================================================================
THE VERIFICATION GATE
================================================================================
A build that fails ANY of these exits non-zero and must not be adopted.

  1. ELF class and machine - ELF64 and x86-64 / AArch64 to match the RID.
  2. Stripped - no .symtab, .strtab or .debug_* section left.
  3. No RPATH or RUNPATH, no TEXTREL.
  4. Dependencies - NEEDED must be a subset of ALLOWED_DEPS in pins.env (glibc
     and its loader only); libstdc++, libgcc_s, libbinaryen, libmimalloc and
     libatomic are named explicitly (FORBIDDEN_DEP_PATTERN). No GLIBCXX_,
     CXXABI_ or GCC_ symbol version may be referenced (the C++ runtime is
     really static). `ldd` must resolve every NEEDED library.
  5. glibc floor - the highest GLIBC_x.y symbol version referenced, CHECKED
     against pins.env: <= 2.28 for both RIDs.
  6. No build paths - none of the scratch source, build, /work or /home paths
     appears in the binary's strings. (The static libstdc++ brings three
     /builddir/... header paths of Red Hat's GCC build with it; they are
     recorded in BUILD-INFO.txt as "Toolchain paths" - not ours, and not a
     failure.)
  7. Configure - binaryen's own configure messages must say "statically linked
     library", -DBUILD_LLVM_DWARF and -UNDEBUG, and must not say "shared
     library", "mimalloc" or -Werror (REQUIRED_ / FORBIDDEN_CONFIGURE_LINES).
  8. Functional - functional-gate.sh RUNS the stripped executable, network
     still off, against gate-fixture.wat (a small module written for this
     repository - no third-party test data):
       a. `wasm-opt --version` is exactly "wasm-opt version 133";
       b. -O0 and -Oz both write a module starting 00 61 73 6d 01 00 00 00;
       c. the -Oz output is no larger than the -O0 output;
       d. the three flag sets the consuming tool passes (pins.env CONSUMER_*)
          are accepted:
            --enable-reference-types --enable-bulk-memory
            --enable-mutable-globals --enable-nontrapping-float-to-int
            --enable-threads  +  --strip-debug -Oz
                              |  --debuginfo -Oz
                              |  --strip-debug --memory-packing -Oz
          each with --fuzz-exec, which runs all eight exports in wasm-opt's
          own interpreter before AND after optimising: the results must agree
          with each other and with EXPECTED_RESULTS;
       e. the --debuginfo output is larger than the --strip-debug output;
       f. each output, read back and executed again, still gives
          EXPECTED_RESULTS.
     Under qemu this really executes the foreign-architecture code.


================================================================================
THE HOST CHECK
================================================================================
After a RID's container build passes, build.sh runs functional-gate.sh ONCE
MORE, directly on the host, when the host can execute that RID natively
(linux-x64 on an x86_64 machine, linux-arm64 on an arm64 machine). That proves
the binary starts on a real distribution - the host's own glibc, none of the
image's libraries - and does the same work there. The result, with the host's
`ldd` output, is output/<rid>/HOST-CHECK.txt. SKIP_HOST_CHECK=1 turns it off.


================================================================================
TROUBLESHOOTING
================================================================================
"neither podman nor docker found"
    Install one (see PREREQUISITES). The script will not install it for you.

"exec format error" / every command in the container dies immediately
    You are building linux-arm64 on x86_64 and the binfmt handler for aarch64
    is not registered. See PREREQUISITES item 2 - or build on an arm64
    machine.

Image pull fails / the tag no longer exists
    quay.io/pypa retires old dated tags. Pick a current tag from
    https://quay.io/organization/pypa, put it in pins.env WITH its digest, and
    say in the commit message which glibc floor that changes. If quay.io itself
    is gone, see THE BARE-HOST ROUTE.

The gate fails "FORBIDDEN dependencies: libstdc++.so.6" (or libgcc_s.so.1)
    -static-libstdc++ / -static-libgcc did not take, or a newer image lacks
    the static archives (gcc-toolset-<n>-libstdc++-devel ships libstdc++.a).
    The Containerfile probe should already have failed in that case.

The gate fails "configure did not print: ..."
    A binaryen update renamed an option or a message. Read
    output/<rid>/cmake-configure.log, decide whether the change is wanted, and
    if it is, update pins.env in the same commit and say why.

The functional gate fails on a --fuzz-exec result
    wasm-opt computed a different value for one of the fixture's exports, or
    the optimised module behaves differently from the original. That is a real
    finding about the binary - do not adopt it. The logs are in
    output/<rid>/gate-run/.

"readelf: Warning: Gap in build notes detected"
    Harmless: the Red Hat toolchain's annobin plugin leaves build-attribute
    notes in its static archives, and readelf warns (and exits 1) about them.
    container-build.sh tolerates it.

"pins.env was not found" after a clone
    The repository-root .gitignore has a blanket '*.env' rule. It is handled by
    the "!*" re-include at the top of ../.gitignore - do not delete that line.
    Check with:
        git check-ignore -v tools/binaryen-native-tools/linux/pins.env

Podman "permission denied" writing ../output/
    Rootless podman maps your user into the container and the :Z mount flag
    handles SELinux relabelling. On a system with an unusual security policy,
    try --userns=keep-id.


================================================================================
THE BARE-HOST ROUTE (no container - for the day the images are gone)
================================================================================
The rule this folder exists for is that the executables can be rebuilt from
this repository alone, years from now. The container images are the one input
that comes from outside, so here is how to build WITHOUT them. The cost is the
glibc floor: a bare-host build's floor is the glibc of the machine that built
it, which must then be recorded in ../BUILD-PROVENANCE.txt as the
compatibility floor of that binary.

On a Debian-based machine of the target architecture, install the compiler
(GCC 11 or newer, for C++20) and the build tools - binaryen needs no -dev
packages:

    sudo apt install build-essential cmake ninja-build file

then run container-build.sh itself outside a container (it reads every pin
from pins.env; only these four come from the environment):

    cd tools/binaryen-native-tools
    sudo ln -sfn "$PWD" /work        # container-build.sh reads /work
    TARGET_RID=linux-x64 GLIBC_MAX=<this machine's glibc, e.g. 2.41> \
    DERIVED_IMAGE=bare-host \
    BASE_IMAGE_REF="$(. /etc/os-release; echo $PRETTY_NAME)" \
    bash linux/container-build.sh

It will warn that the host has network interfaces - the build still fetches
nothing - and the glibc-floor check passes or fails against the GLIBC_MAX you
give it. Debian's GCC ships libstdc++.a with libstdc++-<n>-dev, which
build-essential installs.


================================================================================
ADOPTING A BUILT BINARY INTO THE PACKAGE
================================================================================
  1. Read ../output/<rid>/BUILD-INFO.txt and satisfy yourself the build is the
     one you think it is: binaryen commit, image digest, glibc floor, NEEDED,
     the gate lines - and ../output/<rid>/third-party-evidence.txt, if the
     binaryen version changed (the licence list follows from it).

  2. Copy the executable and its licence files into the package's native tree:

       cp ../output/<rid>/wasm-opt        ../../../native_libraries/<rid>/
       cp ../output/<rid>/LICENSE-*.txt   ../../../native_libraries/<rid>/

     <rid> is linux-x64 or linux-arm64. The licence copies are not optional:
     the licences and notices of everything compiled in travel with the
     binary.

  3. Update ../../../native_libraries/<rid>/wasm-opt.provenance.txt from
     BUILD-INFO.txt (it is the in-repository record beside the binary).

  4. Record the build in ../BUILD-PROVENANCE.txt - copy the values straight out
     of BUILD-INFO.txt.

  5. Run the managed test suite before publishing.


================================================================================
FILES
================================================================================
  README.txt              this document
  pins.env                every version / digest / option pin (edit here
                          only); the Windows and macOS scripts read its
                          platform-neutral keys too
  build.sh                host entry point: images, emulation check,
                          orchestration, the host check
  container-build.sh      the build, the evidence and the gate; runs inside
                          the container
  functional-gate.sh      the functional half of the gate; shared with the
                          host check and the macOS script
  gate-fixture.wat        the module the functional gate optimises; shared by
                          every platform
  Containerfile.x86_64    derived build image for linux-x64
  Containerfile.aarch64   derived build image for linux-arm64
  ../output/              build results (git-ignored)
================================================================================

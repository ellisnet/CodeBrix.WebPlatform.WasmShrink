<#
=============================================================================================
build.wasm-opt.ps1 - build wasm-opt.exe for win-x64, from this repository only
=============================================================================================

  NEVER YET RUN. Written on Linux on 2026-11-18, where it cannot run. Expect to fix something
  on the first real run; fix it IN THE SCRIPT and record it in ..\BUILD-PROVENANCE.txt, then
  rewrite this header and README.txt's status block with what the run established.

USAGE (from a PowerShell prompt; the script finds Visual Studio, cmake and ninja itself):

    cd tools\binaryen-native-tools\windows
    .\build.wasm-opt.ps1
    .\build.wasm-opt.ps1 -BuildRoot D:\cbx-wasm-opt

WHAT IT DOES
  * copies ..\binaryen (the vendored, unmodified snapshot) to a scratch folder and builds
    there - ..\binaryen is never written to;
  * configures binaryen with MSVC through CMake's Ninja generator, from a vcvarsall x64
    environment, with the platform-neutral options from ..\linux\pins.env plus
        -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded   (static CRT, /MT - no Visual C++
                                                      Redistributable needed; binaryen's own
                                                      CMakeLists sets the same for non-Debug
                                                      MSVC builds, this states it)
    and builds the wasm-opt target ONLY (Release);
  * runs the gate (README.txt, THE GATE) and writes ..\output\win-x64\.

  It downloads nothing and installs nothing. Anything missing is named, with the command that
  installs it, and the script stops. win-arm64 is not a CodeBrix.WebPlatform.WasmShrink RID
  and is not built.
=============================================================================================
#>

[CmdletBinding()]
param(
    # Where cmake builds and the gate runs. MSVC has no -ffile-prefix-map, and binaryen keeps
    # assert() on, which embeds __FILE__ - so the scratch path lands in the executable. It
    # defaults to a short folder at the root of the system drive so that no user-profile path
    # (C:\Users\<name>\...) is baked into a shipped binary; the gate fails if one is.
    [string] $BuildRoot = (Join-Path $env:SystemDrive 'cbx-wasm-opt')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$ToolsDir  = Split-Path -Parent $ScriptDir
$OutputDir = Join-Path $ToolsDir 'output'
$Rid       = 'win-x64'

# ---------------------------------------------------------------------------------------------
# Pins - ..\linux\pins.env is the one source of truth. Multi-line "..." values are joined with
# newlines (EXPECTED_RESULTS, LICENCE_FILES, ...); '...' values are taken literally.
# ---------------------------------------------------------------------------------------------
function Read-Pins {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "pins.env was not found at $Path. It is part of the repository - if it is missing after a clone, check the root .gitignore's blanket '*.env' rule (see ..\.gitignore)."
    }
    $pins = @{}
    $key = $null
    $acc = $null
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($null -ne $key) {
            if ($line.EndsWith('"')) {
                $acc += "`n" + $line.Substring(0, $line.Length - 1)
                $pins[$key] = $acc
                $key = $null
            } else {
                $acc += "`n" + $line
            }
            continue
        }
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $eq = $trimmed.IndexOf('=')
        if ($eq -lt 1) { continue }
        $k = $trimmed.Substring(0, $eq).Trim()
        if ($k -notmatch '^[A-Z0-9_]+$') { continue }
        $value = $trimmed.Substring($eq + 1)
        if ($value.StartsWith('"')) {
            if ($value.Length -ge 2 -and $value.EndsWith('"')) {
                $pins[$k] = $value.Substring(1, $value.Length - 2)
            } else {
                $key = $k
                $acc = $value.Substring(1)
            }
        } elseif ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2) {
            $pins[$k] = $value.Substring(1, $value.Length - 2)
        } else {
            $pins[$k] = $value
        }
    }
    foreach ($required in @('BINARYEN_DIR', 'BINARYEN_VERSION', 'BINARYEN_TAG', 'BINARYEN_COMMIT', 'EXE_NAME',
                            'BINARYEN_CMAKE_OPTIONS', 'BUILD_TARGET', 'LICENCE_FILES', 'CONSUMER_FEATURES',
                            'CONSUMER_RELEASE_FLAGS', 'CONSUMER_DEBUG_FLAGS', 'CONSUMER_PACKING_FLAGS',
                            'EXPECTED_RESULTS')) {
        if (-not $pins.ContainsKey($required)) { throw "pins.env has no $required." }
    }
    return $pins
}

$Pins      = Read-Pins (Join-Path $ToolsDir 'linux\pins.env')
$SourceDir = Join-Path $ToolsDir $Pins.BINARYEN_DIR
$ExeName   = "$($Pins.EXE_NAME).exe"
$Fixture   = Join-Path $ToolsDir 'linux\gate-fixture.wat'

# DLLs the shipped executable may import: the operating system only. With the static CRT there
# must be no VCRUNTIME*, MSVCP*, ucrtbase or api-ms-win-crt-* import - the gate fails on any.
$AllowedImports = @('KERNEL32.dll', 'ADVAPI32.dll', 'USER32.dll', 'SHELL32.dll', 'ole32.dll',
                    'bcrypt.dll', 'ntdll.dll', 'SHLWAPI.dll', 'WS2_32.dll')

# ---------------------------------------------------------------------------------------------
# Tools: Visual Studio (vswhere + vcvarsall), cmake, ninja. Checked, never installed.
# ---------------------------------------------------------------------------------------------
function Find-VisualStudio {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw @"
Visual Studio was not found (no vswhere.exe). Install Visual Studio 2022 or newer, or the Build
Tools, with the "Desktop development with C++" workload. This script does not install anything:
    winget install Microsoft.VisualStudio.2022.BuildTools
"@
    }
    $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $path) { throw "No Visual Studio instance with the C++ x64/x86 build tools was found (vswhere)." }
    return $path.Trim()
}

function Import-DeveloperEnvironment {
    param([Parameter(Mandatory)][string] $VsPath, [Parameter(Mandatory)][string] $VcVarsArch)
    $vcvars = Join-Path $VsPath 'VC\Auxiliary\Build\vcvarsall.bat'
    if (-not (Test-Path -LiteralPath $vcvars)) { throw "vcvarsall.bat not found at $vcvars" }
    $lines = & cmd.exe /s /c "`"$vcvars`" $VcVarsArch > nul && set"
    if ($LASTEXITCODE -ne 0) { throw "vcvarsall.bat $VcVarsArch failed - is the matching MSVC toolset installed?" }
    foreach ($line in $lines) {
        $eq = $line.IndexOf('=')
        if ($eq -gt 0) { [Environment]::SetEnvironmentVariable($line.Substring(0, $eq), $line.Substring($eq + 1), 'Process') }
    }
    foreach ($tool in @('cl.exe', 'link.exe', 'dumpbin.exe')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not on PATH after vcvarsall $VcVarsArch." }
    }
}

function Find-Tool([string] $Exe, [string] $Hint) {
    $cmd = @(Get-Command $Exe -ErrorAction SilentlyContinue)[0]
    if ($cmd) { return $cmd.Definition }
    throw @"
$Exe was not found on PATH (after vcvarsall). Install it - this script does not:
    $Hint
"@
}

function Get-PeMachine([string] $Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $pe = [BitConverter]::ToInt32($bytes, 0x3C)
    return [BitConverter]::ToUInt16($bytes, $pe + 4)
}

$script:GateLines    = New-Object System.Collections.Generic.List[string]
$script:GateFailures = New-Object System.Collections.Generic.List[string]
function Add-GatePass([string] $Message) { $l = "  [ok] $Message"; Write-Host $l; $script:GateLines.Add($l) }
function Add-GateFail([string] $Message) { $l = "  [FAIL] $Message"; Write-Host $l; $script:GateLines.Add($l); $script:GateFailures.Add($Message) }

function Get-WasmMagic([string] $Path) {
    $b = [System.IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 8) { return '' }
    return (($b[0..7] | ForEach-Object { $_.ToString('x2') }) -join '')
}

# Runs wasm-opt with the given arguments; returns @{ Code; Output }.
function Invoke-WasmOpt([string] $Exe, [string[]] $Arguments) {
    $output = & $Exe @Arguments 2>&1 | ForEach-Object { "$_" }
    return @{ Code = $LASTEXITCODE; Output = @($output) }
}

function Test-Results([string[]] $Output, [string[]] $Expected) {
    $missing = @($Expected | Where-Object { $Output -notcontains "[fuzz-exec] note result: $_" })
    if ($Output -contains '[fuzz-exec] optimization passes changed results') { $missing += '(wasm-opt reported: optimization passes changed results)' }
    return $missing
}

# The same eight checks as ..\linux\functional-gate.sh.
function Invoke-FunctionalGate([string] $Exe, [string] $RunDir) {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $features = $Pins.CONSUMER_FEATURES -split '\s+' | Where-Object { $_ }
    $expected = @($Pins.EXPECTED_RESULTS -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $magic = '0061736d01000000'

    $v = Invoke-WasmOpt $Exe @('--version')
    $versionLine = @($v.Output)[0]
    if ($versionLine -eq "wasm-opt version $($Pins.BINARYEN_VERSION)") { Add-GatePass "--version: $versionLine" }
    else { Add-GateFail "--version said '$versionLine', expected 'wasm-opt version $($Pins.BINARYEN_VERSION)'" }

    foreach ($level in @('O0', 'Oz')) {
        $out = Join-Path $RunDir "fixture-$level.wasm"
        $r = Invoke-WasmOpt $Exe (@($Fixture) + $features + @("-$level", '-o', $out))
        $r.Output | Set-Content -LiteralPath (Join-Path $RunDir "$level.log")
        if ((Test-Path -LiteralPath $out) -and (Get-WasmMagic $out) -eq $magic) { Add-GatePass "-${level}: wasm magic + version 1 ($((Get-Item $out).Length) bytes)" }
        else { Add-GateFail "-${level}: no valid wasm output (exit $($r.Code)): $($r.Output -join ' | ')" }
    }
    $o0 = Join-Path $RunDir 'fixture-O0.wasm'; $oz = Join-Path $RunDir 'fixture-Oz.wasm'
    if ((Test-Path $o0) -and (Test-Path $oz)) {
        $s0 = (Get-Item $o0).Length; $sz = (Get-Item $oz).Length
        if ($sz -le $s0) { Add-GatePass "-Oz output ($sz bytes) is no larger than -O0 output ($s0 bytes)" }
        else { Add-GateFail "-Oz output ($sz bytes) is LARGER than -O0 output ($s0 bytes)" }
    }

    $sets = [ordered]@{ release = $Pins.CONSUMER_RELEASE_FLAGS; debug = $Pins.CONSUMER_DEBUG_FLAGS; packing = $Pins.CONSUMER_PACKING_FLAGS }
    foreach ($name in $sets.Keys) {
        $flags = $sets[$name] -split '\s+' | Where-Object { $_ }
        $out = Join-Path $RunDir "fixture-$name.wasm"
        $r = Invoke-WasmOpt $Exe (@($Fixture) + $features + $flags + @('--fuzz-exec', '-o', $out))
        $r.Output | Set-Content -LiteralPath (Join-Path $RunDir "$name.log")
        if ($r.Code -ne 0 -or -not (Test-Path -LiteralPath $out) -or (Get-WasmMagic $out) -ne $magic) {
            Add-GateFail "$name set rejected or produced no valid wasm (exit $($r.Code)): $($sets[$name]) | $($r.Output -join ' | ')"
            continue
        }
        $missing = @(Test-Results $r.Output $expected)
        if ($missing.Count -gt 0) { Add-GateFail "$name set: --fuzz-exec results wrong or missing: $($missing -join '; ')" }
        else { Add-GatePass "$name set accepted ($((Get-Item $out).Length) bytes), --fuzz-exec $($expected.Count)/$($expected.Count) results before = after = expected: $($sets[$name])" }
    }

    $rel = Join-Path $RunDir 'fixture-release.wasm'; $dbg = Join-Path $RunDir 'fixture-debug.wasm'
    if ((Test-Path $rel) -and (Test-Path $dbg)) {
        $sr = (Get-Item $rel).Length; $sd = (Get-Item $dbg).Length
        if ($sd -gt $sr) { Add-GatePass "--debuginfo output ($sd bytes) is larger than --strip-debug output ($sr bytes): name section kept / stripped" }
        else { Add-GateFail "--debuginfo output ($sd bytes) is not larger than --strip-debug output ($sr bytes)" }
    }

    foreach ($name in $sets.Keys) {
        $f = Join-Path $RunDir "fixture-$name.wasm"
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $r = Invoke-WasmOpt $Exe (@($f) + $features + @('--fuzz-exec', '-o', (Join-Path $RunDir "readback-$name.wasm")))
        $r.Output | Set-Content -LiteralPath (Join-Path $RunDir "readback-$name.log")
        $missing = @(Test-Results $r.Output $expected)
        if ($r.Code -eq 0 -and $missing.Count -eq 0) { Add-GatePass "fixture-$name.wasm read back and re-run: $($expected.Count)/$($expected.Count) expected results" }
        else { Add-GateFail "fixture-$name.wasm read back (exit $($r.Code)): $($missing -join '; ')" }
    }
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------
$started = Get-Date
if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'src\tools\wasm-opt.cpp'))) {
    throw "the vendored binaryen source is missing from $SourceDir. It is part of the repository - restore it from git."
}
$projectLine = Select-String -LiteralPath (Join-Path $SourceDir 'CMakeLists.txt') -Pattern '^project\(binaryen LANGUAGES C CXX VERSION (\d+)\)'
if (-not $projectLine -or $projectLine.Matches[0].Groups[1].Value -ne $Pins.BINARYEN_VERSION) {
    throw "binaryen\CMakeLists.txt does not declare version $($Pins.BINARYEN_VERSION) (pins.env)."
}
if (-not (Test-Path -LiteralPath $Fixture)) { throw "$Fixture is missing; it is part of the repository." }

$vs = Find-VisualStudio
$hostArch = $env:PROCESSOR_ARCHITECTURE   # AMD64 or ARM64 (ARM64 Windows runs x64 code too)
Import-DeveloperEnvironment -VsPath $vs -VcVarsArch $(if ($hostArch -eq 'ARM64') { 'arm64_amd64' } else { 'x64' })
$cmake = Find-Tool 'cmake.exe' 'winget install Kitware.CMake   (or the "C++ CMake tools for Windows" Visual Studio component)'
$ninja = Find-Tool 'ninja.exe' 'winget install Ninja-build.Ninja   (or the "C++ CMake tools for Windows" Visual Studio component, which ships ninja)'

$scratch = Join-Path $BuildRoot 'src'
$build   = Join-Path $BuildRoot 'build'
$out     = Join-Path $OutputDir $Rid

Write-Host ""
Write-Host "=============================================================================="
Write-Host " BUILD $Rid  (binaryen $($Pins.BINARYEN_VERSION), $($Pins.BINARYEN_TAG), commit $($Pins.BINARYEN_COMMIT))"
Write-Host "=============================================================================="
if (Test-Path -LiteralPath $BuildRoot) { Remove-Item -LiteralPath $BuildRoot -Recurse -Force }
New-Item -ItemType Directory -Path $BuildRoot | Out-Null
Copy-Item -LiteralPath $SourceDir -Destination $scratch -Recurse
New-Item -ItemType Directory -Path $build | Out-Null

$cmakeArgs = @('-S', $scratch, '-B', $build, '-G', 'Ninja', "-DCMAKE_MAKE_PROGRAM=$ninja",
               '-DCMAKE_C_COMPILER=cl', '-DCMAKE_CXX_COMPILER=cl',
               '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded') +
             @($Pins.BINARYEN_CMAKE_OPTIONS -split '\s+' | Where-Object { $_ })
Write-Host "  cmake $($cmakeArgs -join ' ')"
$configure = & $cmake @cmakeArgs 2>&1 | ForEach-Object { "$_" }
$configure | Set-Content -LiteralPath (Join-Path $BuildRoot 'configure.log') -Encoding UTF8
if ($LASTEXITCODE -ne 0) { $configure | Select-Object -Last 60 | Write-Host; throw "cmake configure failed" }
$summary = @($configure | Where-Object { $_ -match '^-- (Building|Linking)' } | ForEach-Object { $_ -replace '^-- ', '' })
$summary | ForEach-Object { Write-Host "    $_" }

$buildLog = & $cmake --build $build --target $Pins.BUILD_TARGET 2>&1 | ForEach-Object { "$_" }
$buildLog | Set-Content -LiteralPath (Join-Path $BuildRoot 'build.log') -Encoding UTF8
if ($LASTEXITCODE -ne 0) { $buildLog | Select-String -Pattern 'error' | Select-Object -First 60 | Write-Host; throw "build failed" }
$warnings = @($buildLog | Where-Object { $_ -match ': warning ' }).Count

$built = Join-Path $build "bin\$ExeName"
if (-not (Test-Path -LiteralPath $built)) { throw "the build did not produce $built" }
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null
Copy-Item -LiteralPath $built -Destination $out
$exe = Join-Path $out $ExeName
$licenceNames = @()
foreach ($entry in ($Pins.LICENCE_FILES -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $name, $from = $entry -split ':', 2
    Copy-Item -LiteralPath (Join-Path $ToolsDir ($from -replace '/', '\')) -Destination (Join-Path $out $name)
    $licenceNames += $name
}

# ---- THE GATE ------------------------------------------------------------------------------
Write-Host "--- verifying ---"
$machine = Get-PeMachine $exe
if ($machine -eq 0x8664) { Add-GatePass ('PE machine 0x{0:X4} (x64)' -f $machine) }
else { Add-GateFail ('PE machine 0x{0:X4}, expected 0x8664' -f $machine) }

$importsText = & dumpbin.exe /nologo /imports $exe
$imports = @($importsText | ForEach-Object { if ("$_" -match '^\s{4}(\S+\.dll)\s*$') { $Matches[1] } } | Sort-Object -Unique)
$crt = @($imports | Where-Object { $_ -match '^(VCRUNTIME|MSVCP|ucrtbase|api-ms-win-crt)' })
$unexpected = @($imports | Where-Object { $AllowedImports -notcontains $_ })
if ($imports.Count -eq 0) { Add-GateFail 'no imports parsed from dumpbin /imports - check the parser against its output' }
if ($crt.Count -gt 0) { Add-GateFail "C runtime DLLs imported (static CRT expected): $($crt -join ' ')" }
if ($unexpected.Count -gt 0) { Add-GateFail "unexpected imports: $($unexpected -join ' ')" }
elseif ($imports.Count -gt 0) { Add-GatePass "imports are OS-only: $($imports -join ' ') (no VCRUNTIME / MSVCP / ucrtbase / api-ms-win-crt)" }

$pdbs = @(Get-ChildItem -LiteralPath (Join-Path $build 'bin') -Filter '*.pdb' -ErrorAction SilentlyContinue)
Add-GatePass "no .pdb shipped ($($pdbs.Count) in the build folder; Release links without /DEBUG)"

# No user-profile or repository path in the binary (see the -BuildRoot comment above).
$text = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($exe))
$leaks = @(@($env:USERPROFILE, $ToolsDir) | Where-Object { $_ -and $text.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
if ($leaks.Count -gt 0) { Add-GateFail "paths found in the binary: $($leaks -join ' ')" }
else { Add-GatePass "no user-profile or repository path in the binary (build root $BuildRoot is, as assert() file names - recorded)" }

foreach ($want in @('Building libbinaryen as statically linked library.', 'Building with /DBUILD_LLVM_DWARF', 'Building with /UNDEBUG')) {
    if ($summary -contains $want) { Add-GatePass "configure: $want" } else { Add-GateFail "configure did not print: $want" }
}

Write-Host "  --- functional gate (the checks of ..\linux\functional-gate.sh) ---"
Invoke-FunctionalGate $exe (Join-Path $out 'gate-run')

if ($script:GateFailures.Count -gt 0) {
    throw "VERIFICATION FAILED for $Rid ($($script:GateFailures.Count) check(s)). output\$Rid is left for inspection but must not be adopted."
}

# ---- RECORD ---------------------------------------------------------------------------------
$sha  = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $exe).Length
$gzPath = Join-Path $BuildRoot 'wasm-opt.exe.gz'
$fs = [System.IO.File]::Create($gzPath)
$gz = New-Object System.IO.Compression.GZipStream($fs, [System.IO.Compression.CompressionLevel]::Optimal)
$bytes = [System.IO.File]::ReadAllBytes($exe); $gz.Write($bytes, 0, $bytes.Length); $gz.Dispose(); $fs.Dispose()
$gzSize = (Get-Item -LiteralPath $gzPath).Length
$cl = ((& cmd.exe /c 'cl.exe 2>&1') | Select-Object -First 1)
$cmakeVersion = ((& $cmake --version) | Select-Object -First 1)
$ninjaVersion = (& $ninja --version)
$info = @"
wasm-opt (binaryen) - build information
==============================================================================
RID              : $Rid
Built            : $($started.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) UTC
Build duration   : $([int]((Get-Date) - $started).TotalSeconds)s
Built by         : tools/binaryen-native-tools/windows/build.wasm-opt.ps1
Build host       : $env:COMPUTERNAME, $env:PROCESSOR_ARCHITECTURE, $([Environment]::OSVersion.VersionString)
Visual Studio    : $vs
Compiler         : $cl
cmake / ninja    : $cmakeVersion / $ninjaVersion
Build root       : $BuildRoot

binaryen         : $($Pins.BINARYEN_VERSION), tag $($Pins.BINARYEN_TAG), commit $($Pins.BINARYEN_COMMIT)
Source           : tools/binaryen-native-tools/binaryen/ (vendored, unmodified; copied to scratch)
cmake options    : $($cmakeArgs[4..($cmakeArgs.Count - 1)] -join ' ')
target           : $($Pins.BUILD_TARGET) only
Compiler warnings: $warnings
binaryen's configure summary:
$(($summary | ForEach-Object { "  $_" }) -join "`n")

Result
------------------------------------------------------------------------------
File             : $ExeName
Size             : $size bytes
Size (gzip)      : $gzSize bytes (.NET GZipStream Optimal - NOT the same as gzip -9)
SHA256           : $sha
PE machine       : $('0x{0:X4}' -f $machine)
Imports          : $($imports -join ' ')
Licences beside it: $($licenceNames -join ' ')

Gate
------------------------------------------------------------------------------
$($script:GateLines -join "`n")
"@
$info | Set-Content -LiteralPath (Join-Path $out 'BUILD-INFO.txt') -Encoding UTF8
Get-ChildItem -LiteralPath $out -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant(), $_.Name
} | Set-Content -LiteralPath (Join-Path $out 'SHA256SUMS.txt') -Encoding ASCII
Write-Host "  $exe"
Write-Host "  sha256 $sha"
Write-Host "Done. Adopt with ADOPTING A BUILT BINARY in README.txt."

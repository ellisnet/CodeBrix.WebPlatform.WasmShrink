================================================================================
tools/binaryen-native-tools/unstripped - pre-strip executables, LOCAL ONLY
================================================================================

THIS FOLDER IS GIT-IGNORED. Only this README is committed. The owner decided
(2026-11-18) that the unstripped executables are NOT committed to this
repository; they are kept here, on the machine that built them, so they can
be retrieved if a crash report from a shipped wasm-opt ever needs symbols. A
fresh clone has none of them. Nothing here is shipped, and nothing here is an
input to any build or pack step.

(Unlike ../output/, which every build wipes and rewrites, no script writes to
or deletes from this folder: files are copied here by hand when a build is
adopted, so they survive later builds.)

One folder per runtime identifier, mirroring ../../../native_libraries/<rid>/:

  <rid>/wasm-opt     the executable as linked, before `strip` - it has the
                     symbol table that `strip` removes, and no DWARF (the
                     build passes no -g). The build writes it to
                     ../output/<rid>/unstripped/wasm-opt
  SHA256SUMS         `shasum -a 256 -c SHA256SUMS` from this folder

Which twin belongs to which shipped executable: the LC_UUID is the same in
both -
    dwarfdump --uuid <rid>/wasm-opt ../../../native_libraries/<rid>/wasm-opt
and the sha256 is the "SHA256 as linked" line of that RID's entry in
../BUILD-PROVENANCE.txt and of its wasm-opt.provenance.txt.

STORED ON THE BUILD MAC (2026-11-19, binaryen version_133):

  RID        LC_UUID (shipped = twin)              sha256 (as linked)
  ---------  ------------------------------------  ----------------------------
  osx-arm64  F6057FDA-7F14-3C38-95A3-12FE255E43D9  a21e9b062bb49cf55d16be5a538f
                                                   7568fe6a1d9882ba83e46dcb4dcc
                                                   c457e542
  osx-x64    1F9A57FA-3E7E-3ACD-8C13-AA4318591B7F  cf61d64322d3bb2de1670181c921
                                                   b5d15bfd6c3b2729fe596d7626bd
                                                   09246be8

The Linux executables have no twin: their build does not keep the pre-strip
file (linux/README.txt). win-x64 has not been built.

THE RULE
--------------------------------------------------------------------------------
When a newly built executable is adopted into native_libraries/<rid>/, copy
../output/<rid>/unstripped/wasm-opt here in the same step and rewrite
SHA256SUMS. A file here whose LC_UUID no longer matches the shipped one is
stale: replace it, never keep it alongside.
================================================================================

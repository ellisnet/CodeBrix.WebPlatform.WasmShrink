;; =============================================================================================
;; gate-fixture.wat - the module every platform's wasm-opt gate optimises
;; =============================================================================================
;;
;; Hand-written for CodeBrix.WebPlatform.WasmShrink (Apache-2.0, like the rest of this
;; repository). It is NOT taken from binaryen's test suite or anywhere else, and the build
;; downloads nothing to run it. wasm-opt reads this text format directly.
;;
;; What it is for:
;;   * the -O0 / -Oz pair: -Oz must produce a valid module no larger than -O0 (the dead
;;     $never_called function and the constant-foldable code give -Oz something to remove);
;;   * the consumer flag sets in pins.env: it uses each feature those flags enable -
;;     reference types (ref.func / ref.is_null, call_indirect through a funcref table), bulk
;;     memory (memory.fill / memory.copy), mutable globals, non-trapping float-to-int
;;     (i32.trunc_sat_f64_s) and threads (atomic read-modify-write) - so a wasm-opt that did
;;     not accept one of them would fail to validate the input;
;;   * --memory-packing: the data segment carries a long run of zero bytes that the pass can
;;     drop (memory starts zeroed);
;;   * --debuginfo vs --strip-debug: the $names below become the name section, so the
;;     --debuginfo output must be the larger of the two;
;;   * --fuzz-exec: every export takes no arguments and returns a fixed i32, so wasm-opt's own
;;     interpreter can run each one before and after optimising and compare. The expected
;;     values are EXPECTED_RESULTS in pins.env.
;;
;; Change it only together with EXPECTED_RESULTS in pins.env.
;; =============================================================================================
(module
  (type $unary (func (param i32) (result i32)))

  (memory $mem 1)

  (global $counter (mut i32) (i32.const 0))

  (table $fns 2 funcref)
  (elem (table $fns) (i32.const 0) func $square $triple)

  ;; "CodeBrix" at address 16, then 192 zero bytes, then "end".
  (data (memory $mem) (i32.const 16)
    "CodeBrix"
    "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
    "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
    "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
    "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
    "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
    "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
    "end")

  (func $square (type $unary) (param $x i32) (result i32)
    (i32.mul (local.get $x) (local.get $x)))

  (func $triple (type $unary) (param $x i32) (result i32)
    (i32.mul (local.get $x) (i32.const 3)))

  (func $factorial (param $n i32) (result i32)
    (local $acc i32)
    (local.set $acc (i32.const 1))
    (block $done
      (loop $next
        (br_if $done (i32.le_s (local.get $n) (i32.const 1)))
        (local.set $acc (i32.mul (local.get $acc) (local.get $n)))
        (local.set $n (i32.sub (local.get $n) (i32.const 1)))
        (br $next)))
    (local.get $acc))

  ;; Never called and not exported: -Oz removes it.
  (func $never_called (param $a i32) (param $b i32) (result i32)
    (local $i i32)
    (local $sum i32)
    (block $done
      (loop $next
        (br_if $done (i32.ge_s (local.get $i) (local.get $b)))
        (local.set $sum (i32.add (local.get $sum) (i32.mul (local.get $a) (local.get $i))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (local.get $sum))

  ;; 10! = 3628800
  (func (export "factorial_of_10") (result i32)
    (call $factorial (i32.const 10)))

  ;; square(7) + triple(7) = 49 + 21 = 70, both through the funcref table
  (func (export "table_sum") (result i32)
    (i32.add
      (call_indirect $fns (type $unary) (i32.const 7) (i32.const 0))
      (call_indirect $fns (type $unary) (i32.const 7) (i32.const 1))))

  ;; non-trapping float-to-int: 1e30 saturates to INT32_MAX
  (func (export "saturating_convert") (result i32)
    (i32.trunc_sat_f64_s (f64.const 1e30)))

  ;; mutable global: 0 + 5
  (func (export "bump_counter") (result i32)
    (global.set $counter (i32.add (global.get $counter) (i32.const 5)))
    (global.get $counter))

  ;; bulk memory: four bytes of 3 filled at 256, copied to 512, read back = 0x03030303
  (func (export "fill_and_copy") (result i32)
    (memory.fill (i32.const 256) (i32.const 3) (i32.const 4))
    (memory.copy (i32.const 512) (i32.const 256) (i32.const 4))
    (i32.load (i32.const 512)))

  ;; threads: atomic add of 9 to a zeroed word
  (func (export "atomic_add") (result i32)
    (drop (i32.atomic.rmw.add (i32.const 1024) (i32.const 9)))
    (i32.atomic.load (i32.const 1024)))

  ;; the data segment is there: 'C' = 67
  (func (export "data_byte") (result i32)
    (i32.load8_u (i32.const 16)))

  ;; reference types: a function reference is never null
  (func (export "ref_is_null") (result i32)
    (ref.is_null (ref.func $square)))
)

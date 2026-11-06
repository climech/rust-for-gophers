# Unsafe Rust and FFI

## What `unsafe` means

Everything so far is **safe Rust**, where the compiler guarantees memory
safety and freedom from data races. Some things can't be checked by the
compiler: calling C, implementing a data structure with raw pointers, or
talking to hardware. For these there's `unsafe`, which unlocks five extra
abilities:

1. dereferencing raw pointers (`*const T`, `*mut T`);
2. calling `unsafe` functions, including all foreign (C) functions;
3. accessing or modifying `static mut` variables;
4. implementing `unsafe` traits (such as `Send`/`Sync` by hand);
5. accessing fields of `union`s.

That's all. `unsafe` doesn't switch off the borrow checker or type
checking. It marks a block where **you** guarantee invariants that the
compiler can't check, and if you get them wrong the result is undefined
behaviour.

```rust
let x = 42;
let p = &x as *const i32;   // creating raw pointers is safe
let y = unsafe { *p };      // dereferencing is not
```

Go's equivalent is the `unsafe` package (`unsafe.Pointer`, `unsafe.Slice`),
used for similar reasons. The difference is in culture and tooling. In
Rust, `unsafe` blocks are kept small and commented with a `// SAFETY:` note
explaining why the invariants hold. They're wrapped in safe APIs, and
they're checked with **Miri**, an interpreter that detects undefined
behaviour (`cargo +nightly miri test`).

```rust
/// Returns the element at `i` without bounds checking.
///
/// # Safety
/// `i` must be less than `slice.len()`.
pub unsafe fn get_fast<T>(slice: &[T], i: usize) -> &T {
    // SAFETY: the caller guarantees `i < slice.len()`.
    unsafe { slice.get_unchecked(i) }
}
```

The standard library is safe abstractions built over small `unsafe` cores:
`Vec`, `String`, `Mutex`, `Arc`. Most application code never needs
`unsafe`. If you find yourself writing it to get around the borrow checker,
step back and redesign, because that's almost always the wrong fix.

## Calling C

```rust
use std::ffi::{CString, c_char, c_int};

unsafe extern "C" {
    fn strlen(s: *const c_char) -> usize;
    safe fn abs(x: c_int) -> c_int;  // declared safe to call (2024)
}

fn main() {
    let s = CString::new("hello").unwrap(); // NUL-terminated copy
    let n = unsafe { strlen(s.as_ptr()) };
    println!("{n} {}", abs(-3));
}
```

Compared with cgo:

- **No call overhead.** Rust and C share a calling convention and a stack,
  and there's no goroutine stack switch. An FFI call costs about as much as
  a normal function call. cgo calls cost tens of nanoseconds and complicate
  scheduling.
- **Bindings are generated** by `bindgen` from C headers. `cbindgen` goes
  the other way, generating headers for Rust code.
- **Exporting to C** is easy, so Rust can replace C inside an existing
  codebase one library at a time:

```rust
#[unsafe(no_mangle)]
pub extern "C" fn add(a: i32, b: i32) -> i32 { a + b }
```

Build it with `crate-type = ["cdylib"]` or `["staticlib"]` under `[lib]`
in `Cargo.toml`. This is why Rust is common in Python extensions (PyO3,
maturin), Node addons (napi-rs), WebAssembly (`wasm-bindgen`), and inside
[C/C++]{.nobr} projects such as the Linux kernel, Android and browsers. Go's
runtime makes those uses awkward.

## Layout control

```rust
#[repr(C)]          // C-compatible field order and padding
struct Header { magic: u32, len: u16, flags: u16 }

#[repr(u8)]         // enum discriminant is a u8
enum Kind { A = 1, B = 2 }

#[repr(transparent)] // same layout as the single field
struct Fd(i32);
```

Without `#[repr(C)]`, the compiler is free to reorder struct fields to
reduce padding. Go keeps fields in declaration order, so in Go you reorder
them by hand. To see a type's size, use `std::mem::size_of::<T>()`.

# The Basics, Quickly

This chapter covers the syntax you need before the interesting parts. It is
deliberately brief.

## Variables and mutability

```go
x := 5
var y int = 10
x = 6 // fine
```

```rust
let x = 5;
let y: i32 = 10;
x = 6; // error: cannot assign twice to immutable variable
```

Bindings are **immutable by default**. You opt into mutation with `mut`:

```rust
let mut count = 0;
count += 1;
```

This isn't just style. `mut` is part of the ownership system you'll meet in
Chapter 3: the compiler uses it to reason about who can change what.

Rust allows **shadowing**: declaring a new variable with the same name, often
with a different type. It's idiomatic for transforming a value step by step:

```rust
let input = "42";
let input: i64 = input.parse().unwrap(); // new binding, new type
```

In Go, `:=` with the same name in an inner scope also shadows, and linters
warn about it because it's usually a bug. In Rust, shadowing in the same
scope is intentional and common.

Constants are written `const MAX: u32 = 100;` and always need a type.
`static` declares a global with a fixed memory address; Chapter 13 shows
how to make mutable globals safe.

## Scalar types

| Go                      | Rust                            |
|-------------------------|---------------------------------|
| `int8 … int64`          | `i8 … i64`, plus `i128`         |
| `uint8 … uint64`        | `u8 … u64`, plus `u128`         |
| `int`, `uint`           | `isize`, `usize` (pointer-sized) |
| `uintptr`               | `usize`                         |
| `float32`, `float64`    | `f32`, `f64`                    |
| `bool`                  | `bool`                          |
| `byte`                  | `u8`                            |
| `rune`                  | `char` (a Unicode scalar value, 4 bytes) |

Two differences matter in practice.

**Indexes and lengths are `usize`.** Go uses `int` for lengths. Rust uses
`usize`, and there are **no implicit conversions**, not even widening
ones. You'll be writing `as` casts or `try_from` calls:

```rust
let n: i32 = 7;
let v = vec![0u8; 10];
let item = v[n as usize];         // `as` never fails: may truncate/wrap
let m = u16::try_from(70_000i32); // Err(...): checked conversion
```

**Overflow is an error.** In debug builds `255u8 + 1` panics; in release it
wraps. When you mean wrapping, say so explicitly with `wrapping_add`,
`checked_add` (returns `Option`), `saturating_add` or `overflowing_add`.

Integer literals take suffixes (`10u64`, `1_000_000i64`); `_` is a visual
separator, as in Go.

## Tuples and arrays

```rust
let pair: (i32, &str) = (1, "one");
let (n, name) = pair;          // destructuring
let first = pair.0;

let arr: [u8; 4] = [1, 2, 3, 4]; // fixed size, like Go's [4]byte
let zeros = [0; 256];
```

A tuple works like an anonymous struct. The empty tuple `()`, called
**unit**, is what functions with no return value return. Go has no direct
equivalent, but you can think of it as `struct{}`.

Arrays have fixed length and are values, just as in Go. Growable sequences
(`Vec<T>`) and slices (`&[T]`) come in Chapter 9.

## Functions

```rust
fn add(a: i32, b: i32) -> i32 {
    a + b // no semicolon: this is the return value
}

fn divmod(a: u32, b: u32) -> (u32, u32) {
    (a / b, a % b)
}
```

There are no named return values, no variadic functions (macros cover those
uses), no default arguments and no function overloading. Multiple returns
are written as a tuple. Functions may be declared after they're used,
just like in Go.

## Everything is an expression

This is the first real shift in thinking. In Rust, **blocks are expressions**.
The last expression in a block, written without a trailing semicolon, is the
block's value. Adding the semicolon turns it into a statement whose value
is `()`.

```rust
let category = if score > 90 { "high" } else { "low" };

let parsed = {
    let raw = read_config();
    raw.trim().to_lowercase()
}; // `parsed` is the value of the block's final expression
```

`if` replaces the ternary operator Go doesn't have. `match` (Chapter 6) and
even `loop` can produce values too:

```rust
let mut tries = 0;
let result = loop {
    tries += 1;
    if let Some(v) = attempt() {
        break v; // break with a value
    }
};
```

`return` exists for early exits. Ending a function on a bare expression is
the idiomatic way to return its result.

::: warn
A stray semicolon at the end of a function produces the error "mismatched
types: expected `i32`, found `()`". Delete the semicolon.
:::

## Control flow

```rust
if x > 0 { /* braces required, no parens needed */ }

while n > 0 { n -= 1; }

loop { /* infinite, like Go's bare `for {}` */ }

for i in 0..10 { }          // 0 to 9, like `for i := range 10`
for i in 0..=10 { }         // inclusive range
for item in &items { }      // iterate by reference
for (i, item) in items.iter().enumerate() { }

'outer: for row in grid {
    for cell in row {
        if cell == 0 { continue 'outer; }
    }
}
```

Go's single `for` keyword is split into `loop`, `while` and `for … in`.
Rust's `for` always iterates over something that implements `IntoIterator`.
There is no C-style three-clause loop; use a range.

`if` conditions must be `bool`. There is no truthiness, which matches Go.

## Comments and docs

```rust
// line comment
/* block comment */

/// Doc comment for the item that follows. Markdown is supported.
/// Code blocks in doc comments are compiled and run as tests.
fn documented() {}

//! Doc comment for the enclosing module or crate (top of file).
```

In Go, any comment directly above a declaration becomes its documentation.
In Rust, doc comments use their own syntax (`///`), and `cargo doc` renders
them as HTML.

## Naming conventions

Rust uses `snake_case` for functions, variables and modules, `CamelCase` for
types and traits, and `SCREAMING_CASE` for constants. Unlike Go,
capitalisation has **nothing** to do with visibility: items are private
unless marked `pub`. rustc will warn if you break these conventions.

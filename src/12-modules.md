# Modules, Crates and Testing

## Modules are not directories

In Go, a package is a directory and every file in it is part of the
package. In Rust, a **crate** is a tree of **modules** rooted at `lib.rs`
or `main.rs`. Modules are declared explicitly in code, and the file layout
follows those declarations.

```text
src/
├── lib.rs
├── config.rs
└── net/
    ├── mod.rs        (or: src/net.rs, alongside the net/ directory)
    ├── client.rs
    └── server.rs
```

```rust
// src/lib.rs
pub mod config;   // loads src/config.rs
pub mod net;      // loads src/net.rs or src/net/mod.rs

// src/net/mod.rs (or src/net.rs)
pub mod client;   // loads src/net/client.rs
mod server;       // private module
```

A file that isn't reached by a `mod` declaration **isn't compiled at all**.
This trips up nearly everyone at first. A module can also be written inline:
`mod tests { … }`.

So a Go package maps loosely onto a Rust module, and a Go module (one
`go.mod`) onto a Cargo package. Modules are much lighter than Go packages,
though: they're namespaces inside one compilation unit, they can refer to
each other cyclically, and they're often small, a single file or even
an inline block.

## Visibility

Items are private to their module (and its children) by default:

| Go                     | Rust                              |
|------------------------|-----------------------------------|
| `lowercase` (package-private) | no modifier (module-private) |
| `Uppercase` (exported) | `pub`                             |
| `internal/` packages   | `pub(crate)`                      |
| —                      | `pub(super)`, `pub(in path)`      |

`pub(crate)` is the workhorse: visible anywhere in this crate, invisible to
users of the crate. Struct fields have their own visibility, so
`pub struct User { pub name: String, hash: String }` exposes the type but
keeps `hash` private.

## Paths and `use`

```rust
use std::collections::HashMap;
use std::io::{self, Read, Write};
use crate::config::Config;        // absolute path from crate root
use super::helpers;               // parent module
use self::client::Client;         // this module (rarely needed)
use serde::{Deserialize, Serialize};

pub use crate::net::client::Client; // re-export at a nicer path
```

`use` only creates a local alias. It doesn't load anything. External
crates listed in `Cargo.toml` are available by name everywhere. A common
convention: import types directly (`HashMap`), and bring functions in
through their parent module (`io::stdin()`, `fs::read()`), so that the
origin stays visible at the call site.

Re-exporting with `pub use` lets a crate expose a flat public API (`mylib::
Client`) while keeping a deep internal structure. Go can't do this,
because the import path *is* the directory layout.

## Cargo.toml

```toml
[package]
name = "inventory"
version = "0.3.1"
edition = "2024"
rust-version = "1.85"      # minimum supported Rust (MSRV)

[dependencies]
serde = { version = "1", features = ["derive"] }
tokio = { version = "1.40", features = ["full"] }
anyhow = "1"
internal-lib = { path = "../internal-lib" }
fork = { git = "https://github.com/me/fork", branch = "fix" }

[dev-dependencies]          # tests, examples, benches only
proptest = "1"

[features]
default = ["json"]
json = ["dep:serde_json"]

[dependencies.serde_json]
version = "1"
optional = true
```

Some differences from Go modules:

- **Version requirements are ranges.** `"1.40"` means `>=1.40.0, <2.0.0`.
  Cargo picks the *newest* compatible version, unlike Go's minimal version
  selection, and records the choice in `Cargo.lock`. Commit `Cargo.lock`
  for applications. For libraries it's optional; current guidance leans
  towards committing it there too.
- **Different major versions can coexist** in one build (`rand 0.7` and
  `rand 0.8`). Their types are distinct and won't unify, which occasionally
  causes confusing errors. Go handles this through `/v2` import paths.
- **Crates come from crates.io**, a central registry, not from VCS URLs. A
  published version is immutable.
- **Features** are compile-time switches that enable optional code and
  dependencies, somewhat like build tags, but declared and additive.
  Code checks them with `#[cfg(feature = "json")]`.

Useful commands: `cargo add`, `cargo update`, `cargo tree` (like `go mod
graph`), `cargo tree -d` (show duplicate versions), `cargo doc --open`
(docs for your *dependencies* too), and `cargo install` (like `go install`).

## Workspaces

A workspace is a set of packages sharing one `Cargo.lock` and one `target/`
directory, much like `go.work`, and commonly used for monorepos:

```toml
# Cargo.toml at the repository root
[workspace]
members = ["crates/*"]
resolver = "3"

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
```

Member crates then write `serde = { workspace = true }`. Splitting a
large project into several crates in a workspace is also the main way to
**speed up compilation**, because the crate is the unit of parallel and
incremental compilation.

## Conditional compilation

```rust
#[cfg(target_os = "linux")]
fn platform() -> &'static str { "linux" }

#[cfg(not(target_os = "linux"))]
fn platform() -> &'static str { "other" }

if cfg!(debug_assertions) { /* debug builds only */ }
```

This replaces Go's `//go:build` lines and `_linux.go` file suffixes. The
attribute can go on any item, including a single function, a `use` or a
whole `mod`.

## Testing

Testing works much as in Go: it's built in, unit tests sit next to the
code, and `cargo test` runs everything.

```rust
pub fn add(a: i32, b: i32) -> i32 { a + b }

#[cfg(test)]                 // compiled only for `cargo test`
mod tests {
    use super::*;            // see the parent module's private items

    #[test]
    fn adds() {
        assert_eq!(add(2, 2), 4);
    }

    #[test]
    #[should_panic(expected = "overflow")]
    fn overflows() { add(i32::MAX, 1); }

    #[test]
    fn parses() -> Result<(), std::num::ParseIntError> {
        let n: i32 = "42".parse()?;   // tests may return Result
        assert!(n > 0, "expected positive, got {n}");
        Ok(())
    }
}
```

| Go                              | Rust                                   |
|---------------------------------|----------------------------------------|
| `foo_test.go`, same package     | `#[cfg(test)] mod tests` in the same file |
| `package foo_test` (black-box)  | `tests/*.rs` integration tests         |
| `t.Errorf` / `t.Fatalf`         | `assert!`, `assert_eq!` (they panic)   |
| `t.Run` subtests, table tests   | loop over cases, or `rstest` crate     |
| `go test -run Name`             | `cargo test name` (substring filter)   |
| `t.Parallel()`                  | the default; `--test-threads=1` to disable |
| `Example*` functions            | doc tests in `///` comments            |
| `testing.B` benchmarks          | `criterion` or `divan` crates          |
| `go test -fuzz`                 | `cargo fuzz`                           |
| `testdata/`                     | any path; `env!("CARGO_MANIFEST_DIR")` |

Tests run **in parallel threads by default**, so tests that share global
state (environment variables, the current directory, a database) need
their own coordination, for example the `serial_test` crate.

There's no `t.Errorf` that records a failure and keeps going. Assertions
panic, so the first failure stops the test. For table tests, put the case
name in the assertion message:

```rust
#[test]
fn table() {
    let cases = [("1", Some(1)), ("x", None), ("-2", Some(-2))];
    for (input, want) in cases {
        let got = input.parse::<i32>().ok();
        assert_eq!(got, want, "input {input:?}");
    }
}
```

**Doc tests** are code blocks in documentation comments. They're compiled
and run by `cargo test`, which keeps examples in the docs working:

````rust
/// Adds two numbers.
///
/// ```
/// assert_eq!(mylib::add(1, 2), 3);
/// ```
pub fn add(a: i32, b: i32) -> i32 { a + b }
````

**Mocking** is less common than in Go. With no structural interfaces, you
can't define a narrow interface in the test package after the fact. The
usual approaches are a trait at the seam with a fake implementation in
tests, generic parameters, or the `mockall` crate. Many Rust codebases
favour pure functions and integration tests over heavy mocking.

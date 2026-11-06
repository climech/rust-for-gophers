# Getting Started

## The toolchain

Go gives you one `go` binary that does almost everything. Rust splits the job
across a few tools, all installed by **rustup**, the toolchain manager:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup update                  # upgrade to the latest stable
rustup component add clippy rustfmt rust-analyzer
```

| Go                         | Rust                          |
|----------------------------|-------------------------------|
| `go build`                 | `cargo build` (`--release` for optimised) |
| `go run .`                 | `cargo run`                   |
| `go test ./...`            | `cargo test`                  |
| `go vet`, staticcheck      | `cargo clippy`                |
| `gofmt` / `go fmt`         | `cargo fmt` (rustfmt)         |
| `go doc`, pkg.go.dev       | `cargo doc --open`, docs.rs   |
| `go mod init`              | `cargo new` / `cargo init`    |
| `go get pkg@v1`            | `cargo add crate@1`           |
| `go.mod` / `go.sum`        | `Cargo.toml` / `Cargo.lock`   |
| gopls                      | rust-analyzer                 |
| `GOOS=linux GOARCH=arm64`  | `--target aarch64-unknown-linux-gnu` |

**Cargo** is the build system and package manager. It calls `rustc`, the
compiler, which you will rarely invoke directly.

One difference you'll notice straight away is compile time. Go was designed
to compile fast; Rust was not. A clean build of a medium project with
dependencies can take a minute or more. Incremental debug builds are
reasonable. Use `cargo check`, which type-checks without generating code,
for the edit–compile loop, and let rust-analyzer run it in your editor.

::: go
Go cross-compiles out of the box. Rust needs the target's standard library
(`rustup target add aarch64-unknown-linux-gnu`) and often a linker for that
platform. Tools like `cross` or `cargo zigbuild` hide most of this.
:::

## Hello, Cargo

```sh
cargo new hello
cd hello
cargo run
```

This creates:

```text
hello/
├── Cargo.toml
└── src/
    └── main.rs
```

```toml
[package]
name = "hello"
version = "0.1.0"
edition = "2024"

[dependencies]
```

```rust
fn main() {
    println!("Hello, world!");
}
```

`println!` ends in `!` because it is a **macro**, not a function. Macros can
take a variable number of arguments and check the format string at compile
time, which a normal Rust function can't do. Format strings use `{}` where
Go uses verbs:

| Go                         | Rust                                |
|----------------------------|-------------------------------------|
| `fmt.Println(x)`           | `println!("{x}")` or `println!("{}", x)` |
| `fmt.Printf("%v", x)`      | `println!("{}", x)` (needs `Display`) |
| `fmt.Printf("%+v", x)`     | `println!("{:?}", x)` (needs `Debug`) |
| `fmt.Printf("%#v", x)`     | `println!("{:#?}", x)` (pretty `Debug`) |
| `fmt.Sprintf(...)`         | `format!(...)`                      |
| `fmt.Fprintf(os.Stderr..)` | `eprintln!(...)`                    |
| `%5.2f`, `%-10s`, `%x`     | `{:5.2}`, `{:<10}`, `{:x}`          |

Variables can be captured inline (`{name}`), but only simple identifiers
can be captured this way, not expressions like `{user.name}`.

A **crate** is a compilation unit: one library or one binary, which is close
to a Go module that contains a single package. A **package** in Cargo's
sense is a `Cargo.toml` that builds one or more crates. `src/main.rs` is the
root of a binary crate and `src/lib.rs` is the root of a library crate. A
package may have both. Chapter 12 covers modules in detail.

## Editions

Rust promises backward compatibility, like Go's Go 1 promise. Changes that
would break code ship in **editions** (2015, 2018, 2021, 2024), chosen per
crate in `Cargo.toml`. Crates on different editions link together without
any problem. It plays a similar role to the `go` directive in `go.mod`,
which also controls language semantics, such as the per-iteration loop
variable change in Go 1.22.

## Debug vs release

Debug builds (`cargo build`) are unoptimised and can be 10–50× slower than
release builds, much more than the gap you'd see in Go. Integer overflow
panics in debug and wraps in release. Always benchmark with `--release`.

```toml
[profile.release]
lto = true           # cross-crate inlining; slower link, faster binary
codegen-units = 1
strip = true
```

# Macros

Go avoids metaprogramming, and you use `go generate` when you really need
it. Rust has macros as a core feature. You've been using them since page
one: `println!`, `vec!`, `format!`, `#[derive(Debug)]`. You don't need to
write many yourself, but you should know what kinds exist and what they
can do.

## Declarative macros: `macro_rules!`

These are pattern-matching rewrite rules over syntax:

```rust
macro_rules! hashmap {
    ( $( $k:expr => $v:expr ),* $(,)? ) => {{
        let mut m = ::std::collections::HashMap::new();
        $( m.insert($k, $v); )*
        m
    }};
}

let ages = hashmap! { "ann" => 31, "bob" => 27 };
```

`$k:expr` matches an expression, and `$( … ),*` matches a
comma-separated repetition. Other fragment types include `ident`, `ty`,
`pat`, `block`, `tt` (any single token tree) and `literal`. Macros are
*hygienic*: a variable defined inside a macro can't clash with the
caller's variables.

Macros run before type checking, so they can do things functions can't:

- take a variable number of arguments (`vec![1, 2, 3]`);
- check format strings at compile time (`println!`);
- generate items, such as many similar `impl` blocks for different types;
- capture source information (`file!()`, `line!()`, `stringify!(expr)`,
  `include_str!("schema.sql")`).

Reach for a macro only once a function or generic can't do the job. Macro
errors are harder to read and IDE support is weaker.

## Procedural macros

Procedural macros are Rust functions that run **inside the compiler**. They
take a token stream and return new code. There are three kinds:

```rust
#[derive(Serialize)]           // derive: adds impls for a type
struct S { /* ... */ }

#[tokio::main]                 // attribute: rewrites the item
async fn main() {}

let q = sqlx::query!("SELECT 1"); // function-like: arbitrary DSL
```

They live in a separate crate with `proc-macro = true`, and they're usually
written with the `syn` (parsing) and `quote` (code generation) crates.
This is how `serde`, `clap`, `thiserror`, `tokio::main`, `sqlx::query!` and
`tracing::instrument` work.

::: go
A procedural macro does the job of `go generate` + `stringer` + `mockgen`
+ struct-tag reflection, but it runs as part of the normal build. There are
no generated files to commit and nothing goes stale. The price is compile
time, since proc-macro crates (and `syn`) must be built first.
:::

To see what a macro expands to, use `cargo expand` (install it with
`cargo install cargo-expand`). The rust-analyzer "Expand macro" action does
the same in your editor.

## Attributes you'll see often

```rust
#[derive(Debug, Clone)]         // derive impls
#[cfg(test)]                    // conditional compilation
#[test]                         // mark a test
#[allow(dead_code)]             // silence a lint locally
#[must_use]                     // warn if the return value is ignored
#[inline]                       // inlining hint (cross-crate)
#[non_exhaustive]               // callers must add a `_` match arm
#[deprecated(note = "use foo")] // like // Deprecated: comments
#[repr(C)]                      // C-compatible layout (FFI)
```

`#[non_exhaustive]` on a public enum or struct lets a library add variants
or fields later without a breaking change. Downstream `match`es must then
include a wildcard arm.

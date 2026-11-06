# Translating Go Idioms

This chapter takes Go patterns you use every day and shows how each one is
usually expressed in Rust. Translating line by line produces poor Rust, so
the goal here is to translate the *intent*.

## Interfaces for dependency injection

```go
type Store interface {
    Get(ctx context.Context, id string) (*Item, error)
}
type Service struct{ store Store }
```

In Rust, the choice is between generics and trait objects:

```rust
trait Store {
    async fn get(&self, id: &str) -> Result<Item>;
}

// Generic: zero-cost, concrete type known at compile time
struct Service<S: Store> { store: S }

// Trait object: one Service type, store chosen at runtime
struct DynService { store: Arc<dyn DynStore> }
```

Prefer the generic version when the store is fixed per binary and only
swapped in tests. Choose `dyn` when you'd otherwise have generics
spreading through dozens of types. Note that a trait with `async fn` isn't
directly dyn-compatible today, hence `DynStore`, whose methods return
boxed futures. The [`async-trait`]{.nobr} crate generates that for you.

## `context.Context`

`Context` does three jobs in Go, and Rust splits them up:

- **Cancellation**: dropping the future (Chapter 14), `select!` with a
  `CancellationToken`, or `tokio::time::timeout`.
- **Deadlines**: `timeout(dur, fut)` at the call site, rather than a
  deadline carried through every call.
- **Request-scoped values**: explicit parameters or a request struct. For
  logging and trace IDs, `tracing` spans propagate the context
  automatically.

There's no need to add a `ctx` parameter to every function.

## `defer`

Use `Drop` (Chapter 3). For one-off cleanup that isn't tied to a type, the
`scopeguard` crate provides `defer!`:

```rust
let _guard = scopeguard::guard((), |_| println!("cleanup"));
```

Name the binding `_guard`, not `_`. A bare `_` drops the value
immediately, so the cleanup runs right away. This is a classic bug,
and it applies to lock guards too.

## Functional options → builders

```go
srv := NewServer(addr, WithTimeout(5*time.Second), WithTLS(cfg))
```

```rust
let srv = Server::builder(addr)
    .timeout(Duration::from_secs(5))
    .tls(cfg)
    .build()?;
```

```rust
pub struct ServerBuilder { addr: String, timeout: Duration,
                           tls: Option<TlsConfig> }

impl ServerBuilder {
    pub fn timeout(mut self, d: Duration) -> Self {
        self.timeout = d;
        self
    }
    pub fn tls(mut self, c: TlsConfig) -> Self {
        self.tls = Some(c);
        self
    }
    pub fn build(self) -> Result<Server> { /* validate, construct */ }
}
```

Each method takes `self` by value and returns it, so calls chain. For
simple cases, a `Config` struct that implements `Default` and is filled in
with `..Default::default()` is shorter. The `bon` and `typed-builder`
crates can derive builders.

## Embedding → composition

Rust has no struct embedding and no inheritance. Use plain fields and
write the delegating methods yourself. Share behavior through traits with
default methods:

```rust
trait Named {
    fn name(&self) -> &str;
    fn greeting(&self) -> String {        // default method
        format!("Hello, {}", self.name())
    }
}
```

When a Go struct embeds another to "inherit" an interface implementation,
in Rust you implement the trait on the outer type and forward to the inner
field. It's a few more lines, and there's no ambiguity about which method
gets called.

## `any` and type switches

- A closed set of types → an `enum`.
- "Any type with behavior X" → generics or `dyn Trait`.
- Truly dynamic data (JSON of unknown shape) → `serde_json::Value`.
- A heterogeneous registry keyed by type → `HashMap<TypeId, Box<dyn Any>>`.
  This is rare.

## `iota`, `String()`, `stringer`

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum Level { Debug, Info, Warn, Error }

impl std::fmt::Display for Level {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let s = match self {
            Level::Debug => "debug", Level::Info => "info",
            Level::Warn => "warn",   Level::Error => "error",
        };
        f.write_str(s)
    }
}
```

The `strum` crate derives `Display`, `FromStr` and iteration over all
variants. `Level::Warn as u8` gives you the discriminant.

## `init()` and package state

Rust has no `init()` and no code runs before `main`. Initialize state
explicitly in `main` and pass it down, or use `LazyLock` for lazily built
globals (Chapter 13). It's more explicit, and the initialization order
can't surprise you.

## Worker pools

| Go                                         | Rust                     |
|--------------------------------------------|--------------------------|
| N goroutines reading from a jobs channel   | `rayon` `par_iter` (CPU) |
| goroutine per item + `WaitGroup`           | `JoinSet` (async)        |
| buffered channel as semaphore              | `tokio::sync::Semaphore` |
| `errgroup.Group` with `SetLimit`           | `futures::stream::iter(..).buffer_unordered(n)` |

```rust
use futures::{StreamExt, stream};

let results: Vec<_> = stream::iter(urls)
    .map(|u| async move { fetch(&u).await })
    .buffer_unordered(16)        // at most 16 in flight
    .collect()
    .await;
```

## Go gotchas that don't exist in Rust

- **Typed nil interfaces** (`err != nil` when `err` holds a nil `*MyErr`).
  There's no nil.
- **Copying a `sync.Mutex` by value.** Moves and the missing `Copy` impl
  make this impossible.
- **Ranging over a value copy** and writing to it. `iter_mut` exists for
  that.
- **Map writes during iteration**, or concurrent map writes. These don't
  compile.
- **Forgotten `err` checks.** `Result` is `#[must_use]`, and the value
  can't be reached without handling the error.
- **Shadowed `err` in an inner scope.** No `err` variables at all.
- **Slices sharing a backing array after `append`.** The borrow checker
  rules this out.
- **Goroutine leaks on abandoned channels.** Tasks still leak if you're
  careless, but dropping a future cancels it, and channels close when
  their senders are dropped.

## Mistakes Go developers make in Rust

1. **Using `&String`, `&Vec<T>` or `&Box<T>` parameters.** Take `&str`,
   `&[T]` or `&T`.
2. **Putting references in long-lived structs.** Own the data instead.
3. **Writing `Arc<Mutex<…>>` around everything.** Start with clear
   ownership and pass `&mut`. Share only what really needs to be shared.
4. **Modeling OOP hierarchies with traits.** Reach for enums first.
5. **Calling `unwrap()` everywhere in library code.** Propagate with `?`
   and use `expect("why this can't fail")` for invariants.
6. **Blocking inside async code.** Use `spawn_blocking`.
7. **Fighting the borrow checker with `unsafe`.** Don't.
8. **Taking `clone()` as defeat.** Cloning a small `String` at a
   boundary is fine. Profile before you optimize.
9. **Ignoring Clippy.** Run `cargo clippy` often. It teaches idioms.

## Where to go next

- *The Rust Programming Language* ("the book"), free at doc.rust-lang.org.
  Use it as a reference for anything this book skims.
- *Rust for Rustaceans* by Jon Gjengset, for intermediate topics: API
  design, unsafe, async internals.
- *Rust Atomics and Locks* by Mara Bos, the definitive text on Rust
  concurrency, free online.
- The Tokio tutorial at tokio.rs, before you write your first service.
- The Rustonomicon, before you write your first `unsafe` block.
- *Rustlings* exercises and Advent of Code, to drill the borrow checker
  until it becomes second nature.

The quickest way to learn is to rewrite a small Go tool you know well, such
as a CLI, a little HTTP service, or a log parser, in Rust, and to read
every compiler error carefully. The messages are good, and they often tell
you exactly what to change.

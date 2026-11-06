# Error Handling

Go and Rust agree on the basic philosophy: errors are values, returned from
functions and handled explicitly, with no exceptions. Rust adds type-system
support that removes most of the boilerplate and makes errors impossible to
ignore.

## `Result`

```rust
enum Result<T, E> {
    Ok(T),
    Err(E),
}
```

```go
func parsePort(s string) (int, error) {
    n, err := strconv.Atoi(s)
    if err != nil {
        return 0, fmt.Errorf("parse port %q: %w", s, err)
    }
    return n, nil
}
```

```rust
fn parse_port(s: &str) -> Result<u16, std::num::ParseIntError> {
    let n = s.parse::<u16>()?;
    Ok(n)
}
```

A Go function returns a value **and** an error, and by convention you only
look at the value when `err == nil`. That convention isn't enforced:
nothing stops you from using `n` without checking `err`, or from using a
garbage value. A Rust function returns a value **or** an error, and the only
way to reach the `T` inside a `Result` is to handle the `Err` case,
whether by matching, propagating with `?`, or explicitly unwrapping.

`Result` is marked `#[must_use]`, so ignoring a returned `Result` produces a
warning. To discard one deliberately, write `let _ = f();`.

## The `?` operator

`?` does the `if err != nil { return err }` for you:

```rust
fn read_config(path: &str) -> Result<Config, Error> {
    let text = std::fs::read_to_string(path)?;
    let cfg: Config = toml::from_str(&text)?;
    cfg.validate()?;
    Ok(cfg)
}
```

`expr?` evaluates to the `Ok` value, or returns early from the function with
the `Err` value **converted** through the `From` trait into the function's
error type. That conversion is why the two different error types above,
`io::Error` and `toml::de::Error`, can both be propagated as `Error`. It
works as long as `Error` implements `From<io::Error>` and
`From<toml::de::Error>`.

`?` also works on `Option` inside functions that return `Option`: on `None`
it returns `None` early.

::: go
`?` is the boilerplate-free error propagation Go has debated for years.
Rust keeps propagation **visible**: every `?` is a point where the function
may return early, just as every `if err != nil` is in Go. What's missing
compared with idiomatic Go is the *context*, the `"parse port %q: %w"`
part. The next sections cover how to add it.
:::

## Defining error types

For a library, define an enum of the ways things can fail:

```rust
use std::fmt;

#[derive(Debug)]
pub enum ConfigError {
    Io(std::io::Error),
    Parse { line: usize, msg: String },
    MissingField(&'static str),
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Self::Io(e) => write!(f, "reading config: {e}"),
            Self::Parse { line, msg } => {
                write!(f, "line {line}: {msg}")
            }
            Self::MissingField(k) => write!(f, "missing field {k}"),
        }
    }
}

impl std::error::Error for ConfigError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(e) => Some(e),
            _ => None,
        }
    }
}

impl From<std::io::Error> for ConfigError {
    fn from(e: std::io::Error) -> Self { Self::Io(e) }
}
```

The pieces map onto Go as follows:

| Go                                   | Rust                                  |
|--------------------------------------|---------------------------------------|
| `error` interface (`Error() string`) | `std::error::Error` trait + `Display` |
| `var ErrNotFound = errors.New(..)`   | an enum variant                       |
| `errors.Is(err, ErrNotFound)`        | `matches!(err, MyError::NotFound)`    |
| `errors.As(err, &target)`            | `match`, or `err.downcast_ref::<T>()` |
| `fmt.Errorf("..: %w", err)`          | a variant wrapping the source error   |
| `errors.Unwrap(err)`                 | `err.source()`                        |

Callers handle specific errors with an ordinary `match`, and the compiler
checks that every variant is covered:

```rust
match load("app.toml") {
    Ok(cfg) => run(cfg),
    Err(ConfigError::Io(e)) if e.kind() == ErrorKind::NotFound => {
        run(Config::default())
    }
    Err(e) => return Err(e.into()),
}
```

Compared with sentinel errors and `errors.Is` chains, the possible errors
are now visible in the function's signature.

## `thiserror` and `anyhow`

Writing those impls by hand gets tedious. In practice, the ecosystem has
settled on two crates:

**`thiserror`** derives the boilerplate for library error types:

```rust
#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("reading config: {0}")]
    Io(#[from] std::io::Error),
    #[error("line {line}: {msg}")]
    Parse { line: usize, msg: String },
    #[error("missing field {0}")]
    MissingField(&'static str),
}
```

**`anyhow`** provides a single catch-all error type for applications, where
you mostly want to propagate errors with context and report them at the
top level:

```rust
use anyhow::{Context, Result, bail};

fn load_user(id: u64) -> Result<User> {
    let path = format!("users/{id}.json");
    let data = std::fs::read(&path)
        .with_context(|| format!("reading {path}"))?;
    let user: User = serde_json::from_slice(&data)
        .context("decoding user")?;
    if user.disabled {
        bail!("user {id} is disabled");
    }
    Ok(user)
}

fn main() -> Result<()> {
    let u = load_user(42)?;
    println!("{}", u.name);
    Ok(())
}
// Error: reading users/42.json
//
// Caused by:
//     No such file or directory (os error 2)
```

`.context(...)` corresponds to `fmt.Errorf("decoding user: %w", err)`, and
the chain is kept so that you can walk or downcast it. `anyhow::Error` works
like Go's `error` interface: a boxed, type-erased error that any error type
converts into through `?`.

The rule of thumb is **`thiserror` in libraries** (callers need to match on
specific failures) and **`anyhow` in binaries** (you mostly report errors).
The standard library's `Box<dyn std::error::Error + Send + Sync>` is the
no-dependency version of `anyhow::Error`.

## Panics

`panic!` in Rust corresponds to `panic` in Go. It's for bugs and broken
invariants, not for expected failures. Indexing out of bounds,
`unwrap()` on `None`, integer overflow in debug builds and explicit
`panic!("…")` calls all panic.

By default a panic unwinds the stack of the current thread, running
`Drop` for everything on the way. If it reaches the top of the main thread,
the process exits. A panic in another thread kills only that thread, and
`join()` returns it as an `Err`. `std::panic::catch_unwind` exists, playing
roughly the role of `recover`, but it's meant for FFI boundaries and thread
pools, not for control flow. Setting `panic = "abort"` in the Cargo profile
makes panics abort the process immediately, which produces smaller
binaries.

::: go
In Go, HTTP servers commonly `recover` panics per request. Rust web
frameworks run each request as a task, and a panicking task is isolated by
the runtime (Tokio catches it and reports it through the task's
`JoinHandle`). Even so, panics are less common in Rust than in Go: there's
no nil to dereference, and invalid states are often impossible to
construct.
:::

## Useful patterns

```rust
// Collect an iterator of Results: stops at the first error.
let nums: Result<Vec<i32>, _> =
    lines.iter().map(|l| l.parse::<i32>()).collect();

// Option <-> Result
let v = opt.ok_or(MyError::Missing)?;
let o: Option<i32> = res.ok();

// Transform errors
let n = s.parse::<u16>().map_err(|e| ConfigError::Parse {
    line: 1,
    msg: e.to_string(),
})?;

// Fallbacks
let port = env_port().unwrap_or(8080);
let cfg = load().unwrap_or_else(|_| Config::default());
let cfg = load().unwrap_or_default();
```

## Summary

- `Result<T, E>` returns a value *or* an error. You can't touch the value
  without dealing with the error.
- `?` propagates errors and converts them with `From`.
- Libraries define error enums (`thiserror`). Applications use `anyhow` and
  add context with `.context()`.
- `panic!` is for bugs, as in Go, but you'll need it much less often.

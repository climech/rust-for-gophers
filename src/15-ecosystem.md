# A Tour of the Ecosystem

Go's standard library includes an HTTP server, JSON, templating, SQL
interfaces and crypto. Rust's standard library is deliberately small:
collections, I/O, threads, networking primitives, and not much else.
Everything else comes from crates. That sounds worrying, but a stable core
set of crates has become the de facto standard library. This chapter tours
the ones you'll use in nearly every service.

## serde: serialization

Go uses struct tags and reflection. Rust uses **derive macros** that
generate serialization code at compile time, so there's no reflection and
no runtime cost.

```go
type User struct {
    ID      int64    `json:"id"`
    Name    string   `json:"name"`
    Email   *string  `json:"email,omitempty"`
    Roles   []string `json:"roles"`
}
```

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct User {
    id: i64,
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    email: Option<String>,
    #[serde(default)]
    roles: Vec<String>,
}

let u: User = serde_json::from_str(r#"{"id":1,"name":"ann"}"#)?;
let s = serde_json::to_string_pretty(&u)?;
```

`serde` is format-agnostic. The same derives work with `serde_json`,
`toml`, `serde_yaml`, `bincode`, `rmp-serde` (MessagePack), `csv` and
others.

Some differences that matter in practice:

- **Missing fields are errors** unless the field is an `Option` or marked
  `#[serde(default)]`. Go silently fills in zero values.
- **Unknown fields are ignored** by default. Add
  `#[serde(deny_unknown_fields)]` to reject them, the counterpart of
  `DisallowUnknownFields`.
- **Enums map to tagged JSON.** `#[serde(tag = "type")]` turns
  `enum Event { Click { x: i32 }, Key { code: u32 } }` into
  `{"type":"Click","x":5}`, which takes custom `UnmarshalJSON` code in Go.
- For dynamic JSON, use `serde_json::Value`, the counterpart of
  `map[string]any`.

## clap: command-line parsing

```rust
use clap::Parser;

/// Resize images in bulk.
#[derive(Parser)]
#[command(version)]
struct Args {
    /// Input directory
    input: std::path::PathBuf,
    /// Target width in pixels
    #[arg(short, long, default_value_t = 800)]
    width: u32,
    /// Print each file as it is processed
    #[arg(short, long)]
    verbose: bool,
}

fn main() {
    let args = Args::parse(); // --help generated from doc comments
}
```

`clap` covers what `flag` plus `cobra` do in Go: subcommands (as an enum),
environment-variable fallbacks, validation and shell completions.

## tracing: logging and spans

`tracing` is the counterpart of `log/slog`, with structured fields and
*spans*: contexts that attach to everything logged inside them, including
across `.await` points.

```rust
use tracing::{info, instrument, warn};

#[instrument(skip(db))]                 // span with the args as fields
async fn handle(db: &Db, user_id: u64) -> Result<()> {
    info!(attempt = 1, "loading user");
    if db.is_locked().await {
        warn!("db locked");
    }
    Ok(())
}

fn main() {
    tracing_subscriber::fmt().json().init(); // like slog.NewJSONHandler
}
```

The simpler `log` crate, with `env_logger`, still exists and is fine for
small tools.

## HTTP: axum and reqwest

**axum** (built on Tokio and `hyper`) is the most widely used web
framework. Handlers are plain async functions, and their arguments are
*extractors* that parse parts of the request:

```rust
use axum::{Json, Router, extract::{Path, State}, routing::get};
use std::sync::Arc;

#[derive(Clone)]
struct AppState { db: Arc<Db> }

async fn get_user(
    State(st): State<AppState>,
    Path(id): Path<u64>,
) -> Result<Json<User>, AppError> {
    let user = st.db.find_user(id).await?;
    Ok(Json(user))
}

#[tokio::main]
async fn main() {
    let state = AppState { db: Arc::new(Db::connect().await) };
    let app = Router::new()
        .route("/users/{id}", get(get_user))
        .with_state(state);
    let ln = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(ln, app).await.unwrap();
}
```

Compared with `net/http`, there's more type machinery, but the `Path`
parsing, JSON decoding and error-to-response conversion are type-checked.
`AppError` implements axum's `IntoResponse` trait to turn errors into HTTP
status codes. Middleware comes from `tower` (timeouts, rate limits,
tracing, CORS), and these layers can be reused across many frameworks.

**reqwest** is the HTTP client:

```rust
let user: User = reqwest::Client::new()
    .get(format!("{base}/users/{id}"))
    .bearer_auth(token)
    .timeout(Duration::from_secs(5))
    .send().await?
    .error_for_status()?      // non-2xx -> Err (Go makes you check)
    .json().await?;
```

## Databases: sqlx

`sqlx` is async, and its `query!` macros **check SQL against a real
database schema at compile time**:

```rust
let rows = sqlx::query_as!(
    User,
    "SELECT id, name, email FROM users WHERE org_id = $1",
    org_id
)
.fetch_all(&pool)
.await?;
```

If a column is renamed, this fails to compile. If `email` is nullable, the
macro requires `Option<String>` in `User`. (For offline builds and CI, run
`cargo sqlx prepare` to cache the query metadata.) There are alternatives:
`diesel` (a type-safe query builder), `sea-orm` (an ORM), and
`tokio-postgres` / `rusqlite` (direct drivers).

## Choosing crates

There's no single standard, but these signals are reliable: download
counts on crates.io, documentation on docs.rs, the `blessed.rs` and
`lib.rs` indexes, and whether the crate is maintained by a well-known
group ([tokio-rs]{.nobr}, [rust-lang]{.nobr}, RustCrypto, rustls). Keep an eye on your
dependency tree. `cargo tree` and `cargo deny` play the roles of `go mod
graph` and `govulncheck`, and `cargo audit` checks the RustSec advisory
database.

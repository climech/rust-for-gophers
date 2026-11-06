# Async Rust

This is where Go and Rust differ most, and the chapter where your Go
intuition is most likely to mislead you.

## Two designs

**Go** has *stackful* coroutines. Each goroutine has its own growable stack,
and the runtime scheduler multiplexes them onto OS threads. Blocking
operations park the goroutine and the runtime handles it. Every function
can block, so there's no distinction between sync and async code. The cost
is a mandatory runtime, a few KB of stack per goroutine, and no control over
scheduling.

**Rust** has *stackless* coroutines. An `async fn` is compiled into a
**state machine**: a struct holding the local variables that are live at
each `.await`, plus a `poll` method that advances it. There's no built-in
runtime. You pick an **executor** library, nearly always **Tokio**, which
drives these state machines on a thread pool with an epoll/kqueue/io_uring
reactor. A task costs exactly the size of its state machine, often a few
hundred bytes, and a single allocation.

What you give up is uniformity. Async functions can only be awaited from
other async code, a blocking call inside async code stalls the executor
thread, and there are extra concepts to learn: `Future`, `Send` bounds,
`Pin`. This is the "function colouring" problem. Go doesn't have it; Rust
does.

## Hello, Tokio

```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
```

```rust
use std::time::Duration;
use tokio::time::sleep;

async fn fetch(id: u32) -> String {
    sleep(Duration::from_millis(100)).await;
    format!("item {id}")
}

#[tokio::main]
async fn main() {
    let a = fetch(1).await;        // sequential
    println!("{a}");

    let handle = tokio::spawn(fetch(2)); // like `go`, returns a handle
    let b = handle.await.unwrap();       // Err if the task panicked
    println!("{b}");
}
```

`#[tokio::main]` is a macro that sets up the runtime and runs `main`'s
future to completion on it. `tokio::spawn` is the counterpart of `go`: it
schedules an independent **task** that runs concurrently and possibly in
parallel. Tokio's default runtime is multi-threaded and work-stealing, like
Go's scheduler.

## Futures are lazy

::: key
Calling an `async fn` **does nothing** except build a future. Work happens
only when the future is `.await`ed, or handed to an executor with `spawn`.
This is the opposite of `go f()`, which starts immediately.
:::

```rust
let fut = fetch(3);   // nothing has happened yet
// ... later ...
let s = fut.await;    // now it runs
```

The `Future` trait is small:

```rust
pub trait Future {
    type Output;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>)
        -> Poll<Self::Output>; // Poll::Ready(v) or Poll::Pending
}
```

The executor calls `poll`. If the future can't make progress, for instance
because a socket isn't readable yet, it registers the `Waker` from `cx`
with the reactor and returns `Pending`. When the socket becomes readable,
the reactor wakes the task and the executor polls it again. `.await` is
syntax for "poll this inner future, and if it's pending, return pending
from me too". You'll almost never implement `poll` yourself, but this
model explains everything else in this chapter.

## Concurrency without spawning

Because futures are values, you can run several **concurrently within one
task**, with no spawning and no `'static` requirement:

```rust
// Run both, wait for both (like errgroup without goroutines)
let (user, orders) = tokio::join!(get_user(id), get_orders(id));

// Same, but stop at the first error
let (user, orders) = tokio::try_join!(get_user(id), get_orders(id))?;

// Race: first one wins, the others are DROPPED (cancelled)
tokio::select! {
    res = fetch_primary() => handle(res),
    res = fetch_replica() => handle(res),
    _ = sleep(Duration::from_secs(2)) => log("timeout"),
}
```

Futures inside `join!` can borrow local variables, because they don't
outlive the enclosing function. `tokio::spawn` requires `'static` (move
owned data in, or use `Arc`), for the same reason `thread::spawn` does.

For a dynamic number of tasks, use `JoinSet`, which replaces the
`WaitGroup` + results channel pattern:

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();
for url in urls {
    set.spawn(async move { download(&url).await });
}
while let Some(res) = set.join_next().await {
    let body = res??; // JoinError, then the task's own error
    process(body);
}
// Dropping a JoinSet aborts any tasks still running.
```

## Cancellation

In Go, cancellation is cooperative and explicit. You thread a
`context.Context` through every call and check `ctx.Done()`. In Rust async,
**dropping a future cancels it**. The next time it would have been polled,
it simply isn't. Its locals are dropped, running their destructors, so
sockets close and guards release.

```rust
use tokio::time::{timeout, Duration};

match timeout(Duration::from_secs(5), fetch_report()).await {
    Ok(report) => save(report),
    Err(_) => eprintln!("timed out"), // fetch_report() was dropped
}
```

No `ctx` parameter is needed. The losing branches of a `select!`, an
aborted `JoinHandle`, and a dropped `JoinSet` are all cancelled the same
way.

::: warn
Cancellation can happen at **any** `.await`. If a function does
`let x = read_header().await; let y = read_body().await;` and is cancelled
between the two awaits, the header is consumed and lost. This is called
**cancellation safety**, and it matters most in `select!` loops, where a
branch's future is dropped every time another branch wins. Tokio's docs
mark which methods are cancel-safe. For cancellation that needs a graceful
shutdown, use `tokio_util::sync::CancellationToken`, which is the closest
thing to `context.WithCancel`.
:::

A spawned task is **not** cancelled when its `JoinHandle` is dropped. It
keeps running detached, like a goroutine. Call `handle.abort()` to cancel
it.

## The `Send` requirement

On the multi-threaded runtime, a task may move between threads at any
`.await`, so `tokio::spawn` requires the future to be `Send`. A future is
`Send` only if everything it holds **across an await point** is `Send`.
This produces one of the most common async errors:

```rust
async fn bad(state: Arc<std::sync::Mutex<State>>) {
    let guard = state.lock().unwrap();
    do_io().await;               // guard still alive here
    guard.update();
}
// error: future cannot be sent between threads safely
//   ... `MutexGuard<'_, State>` is not `Send`
//   ... held across an await
```

There are two fixes. Usually the best one is not to hold the guard across
the await:

```rust
async fn good(state: Arc<std::sync::Mutex<State>>) {
    let snapshot = {
        let g = state.lock().unwrap();
        g.snapshot()
    };                           // guard dropped here
    let result = do_io_with(snapshot).await;
    state.lock().unwrap().apply(result);
}
```

Otherwise, use `tokio::sync::Mutex`, whose `lock()` is itself async and
whose guard is `Send`. It's slower, so use it only when you really must
hold a lock across an await. The same applies to `Rc` and `RefCell`
across awaits: use `Arc` and a mutex, or restructure.

## Don't block the executor

The Go runtime notices when a goroutine is stuck in a blocking syscall and
moves other goroutines to another thread. Tokio can't do that. If a task
calls `std::thread::sleep`, does synchronous file I/O, takes a contended
`std::sync::Mutex` for a long time, or runs a 200 ms computation, it holds
up every other task scheduled on that worker thread.

- Use the async versions: `tokio::time::sleep`, `tokio::fs`,
  `tokio::net`, async database drivers.
- Move blocking or CPU-heavy work off the executor:

```rust
let hash = tokio::task::spawn_blocking(move || {
    bcrypt::hash(password, 12)   // CPU-heavy, synchronous
}).await??;
```

A rule of thumb: code shouldn't run longer than about 10–100 µs between
`.await` points.

## Async channels and sync primitives

`tokio::sync` has the async counterparts of the earlier primitives:

| Go                         | `tokio::sync`                           |
|----------------------------|-----------------------------------------|
| `make(chan T, n)`          | `mpsc::channel(n)` (bounded)            |
| one-shot result channel    | `oneshot::channel()`                    |
| fan-out to all listeners   | `broadcast::channel(n)`                 |
| "latest value" + notify    | `watch::channel(v)`                     |
| `sync.Mutex`               | `Mutex` (async `lock().await`)          |
| semaphore via buffered chan| `Semaphore`                             |
| `sync.Cond`                | `Notify`                                |

```rust
use tokio::sync::{mpsc, oneshot};

enum Cmd {
    Get { key: String, reply: oneshot::Sender<Option<String>> },
    Set { key: String, val: String },
}

// The "actor" pattern: one task owns the state, others send it messages.
async fn store(mut rx: mpsc::Receiver<Cmd>) {
    let mut map = std::collections::HashMap::new();
    while let Some(cmd) = rx.recv().await {
        match cmd {
            Cmd::Get { key, reply } => {
                let _ = reply.send(map.get(&key).cloned());
            }
            Cmd::Set { key, val } => { map.insert(key, val); }
        }
    }
}
```

The actor pattern maps directly onto a Go goroutine that owns its state and
serves requests from a channel. In Rust it has the added advantage that the
state needs no lock at all.

## A TCP echo server, side by side

```go
ln, _ := net.Listen("tcp", ":7000")
for {
    conn, err := ln.Accept()
    if err != nil { continue }
    go func() {
        defer conn.Close()
        io.Copy(conn, conn)
    }()
}
```

```rust
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let ln = TcpListener::bind("0.0.0.0:7000").await?;
    loop {
        let (mut sock, _) = ln.accept().await?;
        tokio::spawn(async move {
            let (mut r, mut w) = sock.split();
            let _ = tokio::io::copy(&mut r, &mut w).await;
        }); // sock dropped (closed) when the task ends
    }
}
```

The two programs have the same shape. The differences are in the details:
`.await` marks each suspension point, `async move` moves ownership of the
socket into the task, and `Drop` takes the place of `defer conn.Close()`.

## Other things you'll meet

- **Async functions in traits** work natively (since Rust 1.75). If the
  resulting futures must be `Send` for use with `dyn Trait` or across
  spawns, the `async-trait` or `trait-variant` crates help.
- **Async closures**, `async || { … }`, are stable since 1.85.
- **`Pin`** appears because a state machine may contain references into
  itself, so it must not move in memory once polled. `Box::pin(fut)` and
  the `pin!` macro handle this. You'll see `Pin<Box<dyn Future<Output = T>
  + Send>>`, the type-erased future, in trait objects and recursive async
  functions.
- **Streams** (`futures::Stream`, `tokio_stream`) are async iterators. Use
  `while let Some(x) = stream.next().await`.

## Threads or async?

- **Async** for I/O-bound work with many concurrent operations: servers,
  clients, proxies, anything that would have thousands of goroutines in Go.
- **Threads** (plus Rayon) for CPU-bound work, or for a handful of
  long-running workers. Sync code is simpler: no colouring, no `Send`
  puzzles.
- Mixing them is normal: an async server that offloads hashing to
  `spawn_blocking` or to a Rayon pool.

::: go
The biggest mental shift is that **there is no runtime unless you bring
one**, and its behaviour, such as blocking, task placement or cancellation,
is library code you can read and configure. Once you accept that futures
are lazy values and that dropping a future cancels it, most of the
remaining surprises in async Rust follow from those two facts.
:::

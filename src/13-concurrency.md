# Concurrency with Threads

Go makes concurrency cheap and easy to start: write `go f()`, share
memory or pass messages, and run `-race` in CI to catch what you got wrong.
Rust makes it **checked**. The ownership rules you've already learned
extend to threads, and a program with a data race doesn't compile.

## Threads are OS threads

```rust
use std::thread;

let handle = thread::spawn(|| {
    // runs on a new OS thread
    expensive_computation()
});
let result = handle.join().unwrap(); // Err if the thread panicked
```

`thread::spawn` creates a real OS thread, with a megabyte-scale stack and a
kernel-level context switch. It isn't a goroutine. Thousands of threads
are fine; a million aren't. For Go-style "one task per connection" at
scale, Rust uses `async` with a runtime such as Tokio (next chapter). For
CPU-bound parallelism it uses a thread pool such as Rayon (below).

`spawn` requires a `'static` closure (Chapter 5), so the thread can't
borrow from the spawning function. Move data in:

```rust
let data = vec![1, 2, 3];
let h = thread::spawn(move || data.iter().sum::<i32>());
// `data` moved into the thread; unusable here
println!("{}", h.join().unwrap());
```

Unlike a goroutine, a thread can **return a value** through its
`JoinHandle`, so there's no need for a result channel or a variable
captured from outside.

## `Send` and `Sync`

Two marker traits carry all of Rust's thread safety:

- **`Send`**: ownership of a value of this type can be transferred to
  another thread.
- **`Sync`**: a `&T` can be shared between threads. Formally, `T` is
  `Sync` if `&T` is `Send`.

You almost never implement them. The compiler derives them
**automatically** from a type's fields: a struct made of `Send` fields is
`Send`. Nearly everything is both. These are the notable exceptions:

| Type                    | Send | Sync | Why                                  |
|-------------------------|------|------|--------------------------------------|
| `Rc<T>`                 | no   | no   | non-atomic reference count           |
| `Cell<T>`, `RefCell<T>` | yes  | no   | unsynchronised interior mutation     |
| `MutexGuard<T>`         | no   | yes  | must unlock on the locking thread    |
| raw pointers            | no   | no   | compiler can't reason about them     |
| `Arc<T>`                | yes  | yes  | only if `T: Send + Sync`             |
| `Mutex<T>`              | yes  | yes  | only if `T: Send`; the lock adds `Sync` |

(The "yes" entries for wrapper types assume `T` itself is `Send`/`Sync`.)

`thread::spawn` requires its closure to be `Send`. Try to move an `Rc` into
a thread and you get:

```text
error[E0277]: `Rc<Vec<i32>>` cannot be sent between threads safely
```

::: key
Data race freedom in Rust is not a separate feature. It follows directly
from *aliasing XOR mutability* plus `Send`/`Sync`. A data race needs two
threads accessing the same memory, at least one of them writing, without
synchronisation. Ownership rules out unsynchronised shared mutable access
everywhere, and threads are just one more place where the rule applies.
:::

## Shared state: `Arc<Mutex<T>>`

The classic racy Go program:

```go
count := 0
var wg sync.WaitGroup
for i := 0; i < 10; i++ {
    wg.Add(1)
    go func() { defer wg.Done(); count++ }() // DATA RACE
}
wg.Wait()
```

The direct translation doesn't compile, since `count` can't be borrowed
mutably by ten threads at once. The correct version:

```rust
use std::sync::{Arc, Mutex};
use std::thread;

let count = Arc::new(Mutex::new(0));
let mut handles = vec![];
for _ in 0..10 {
    let count = Arc::clone(&count);
    handles.push(thread::spawn(move || {
        *count.lock().unwrap() += 1;
    }));
}
for h in handles { h.join().unwrap(); }
println!("{}", *count.lock().unwrap()); // 10
```

`Arc` provides shared ownership across threads, and `Mutex` provides
synchronised mutation. Note where the data lives.

### The mutex owns the data

```go
type Cache struct {
    mu    sync.Mutex
    items map[string]string // protected by mu (by convention!)
}
```

```rust
struct Cache {
    items: Mutex<HashMap<String, String>>,
}

impl Cache {
    fn get(&self, k: &str) -> Option<String> {
        let items = self.items.lock().unwrap(); // MutexGuard
        items.get(k).cloned()
    } // guard dropped => unlocked
}
```

In Go, a comment tells you that `mu` protects `items`. In Rust, `Mutex<T>`
**contains** the `T`, and the only way to reach it is `lock()`, which
returns a guard. The guard dereferences to `&mut T`, and dropping it
unlocks the mutex. You can't touch the data without the lock, and you
can't forget to unlock. Note that `get` takes `&self`. `Mutex` is an
interior-mutability type (Chapter 11), so many threads can share
`&Cache`.

**Poisoning**: if a thread panics while holding the lock, the mutex is
marked *poisoned* and later `lock()` calls return `Err`, because the data
may be half-updated. Most code just calls `.unwrap()`. The `parking_lot`
crate provides faster mutexes without poisoning.

Other primitives: `RwLock<T>` (`sync.RWMutex`), `Condvar` (`sync.Cond`),
`Barrier`, and `std::sync::atomic::{AtomicU64, AtomicBool, …}`
(`sync/atomic`). For the counter above, an `AtomicU64` with
`fetch_add(1, Ordering::Relaxed)` is the better choice. Atomics take an
explicit memory **ordering**. Go's atomics are always sequentially
consistent (`SeqCst`). When unsure, use `SeqCst`, and use `Relaxed` for
plain counters.

::: warn
Rust prevents data races, not **deadlocks** or higher-level race
conditions. Lock ordering still matters. Watch out for temporaries:
in `match m.lock().unwrap().get(k) { … }` the guard stays alive until the
end of the whole `match`, which can lead to self-deadlock if you lock
again inside an arm. Bind the result to a variable first.
:::

## Scoped threads: borrowing across threads

`thread::scope` lets threads **borrow** local data, because the scope
guarantees that every thread joins before it returns. It's the Rust
version of the `sync.WaitGroup` pattern, with the `Wait()` built in:

```rust
let mut chunks = vec![vec![1, 2], vec![3, 4], vec![5, 6]];
let total = 7;

thread::scope(|s| {
    for chunk in &mut chunks {
        s.spawn(|| {                   // no `move`, no Arc
            for x in chunk.iter_mut() { *x *= total; }
        });
    }
}); // all threads joined here

println!("{chunks:?}"); // [[7, 14], [21, 28], [35, 42]]
```

Each thread gets an exclusive `&mut` to its own chunk, and they all share
`&total`. The borrow checker confirms that the chunks don't overlap. Go
can't check this.

## Channels

```rust
use std::sync::mpsc;   // "multi-producer, single-consumer"

let (tx, rx) = mpsc::channel();         // unbounded
// let (tx, rx) = mpsc::sync_channel(10); // bounded, like make(chan T, 10)

for id in 0..3 {
    let tx = tx.clone();
    thread::spawn(move || {
        tx.send(format!("worker {id} done")).unwrap();
    });
}
drop(tx); // drop our copy so the channel can close

for msg in rx {           // like `for msg := range ch`
    println!("{msg}");
}
```

There are two differences from Go channels.

**Closing is ownership.** There's no `close(ch)`. A channel closes when
every `Sender` has been dropped. Then `recv()` returns `Err` and the
receiving loop ends. This removes Go's "send on closed channel" panic and
the question of who is supposed to close the channel. The `drop(tx)`
above is the Rust counterpart of a `close` after `wg.Wait()`. Forgetting
it is the Rust counterpart of a goroutine blocked forever on `range ch`.

**Sending moves the value.** After `tx.send(v)`, `v` belongs to the
receiver, so the sender can't keep mutating something it has just handed
off. That's "share memory by communicating" enforced by the type system.

The standard library has no `select`. For thread-based code, the
`crossbeam-channel` crate provides MPMC channels and a `select!` macro. In
async code, Tokio's channels and `tokio::select!` fill this role (next
chapter).

## Data parallelism with Rayon

For CPU-bound work, the Rayon crate turns sequential iterators into
parallel ones with a work-stealing pool:

```rust
use rayon::prelude::*;

let sum: u64 = (0..10_000_000u64)
    .into_par_iter()
    .filter(|n| n % 3 == 0)
    .map(|n| n * n)
    .sum();

let mut images = load_all();
images.par_iter_mut().for_each(|img| img.resize(800, 600));
```

The `Send`/`Sync` bounds on the closures ensure that this is safe. If the
closure captured an `Rc` or mutated shared state without a lock, it
wouldn't compile. In Go you'd build a worker pool with goroutines, a
channel and a `WaitGroup`.

## Global state

```rust
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{LazyLock, Mutex};

static REQUESTS: AtomicUsize = AtomicUsize::new(0);
static REGISTRY: LazyLock<Mutex<Vec<String>>> =
    LazyLock::new(|| Mutex::new(Vec::new()));

fn handle() {
    REQUESTS.fetch_add(1, Ordering::Relaxed);
    REGISTRY.lock().unwrap().push("x".into());
}
```

A `static` must be `Sync`, because any thread can reach it. `static mut`
exists but needs `unsafe` to touch, and the 2024 edition denies references
to it by default. Use atomics or locks instead. A package-level `var` in
Go, by contrast, is shared mutable state with no protection at all.

## Summary

| Go                         | Rust                                     |
|----------------------------|------------------------------------------|
| `go f()`                   | `thread::spawn` (OS thread) / `tokio::spawn` (task) |
| `sync.WaitGroup`           | `JoinHandle::join`, `thread::scope`      |
| `sync.Mutex` + comment     | `Mutex<T>` that owns `T`                 |
| `sync.RWMutex`             | `RwLock<T>`                              |
| `sync/atomic`              | `std::sync::atomic` (explicit ordering)  |
| `sync.Once`, `OnceValue`   | `OnceLock`, `LazyLock`                   |
| `chan T` (buffered)        | `mpsc::sync_channel`, crossbeam, tokio::sync::mpsc |
| `close(ch)`                | drop all senders                         |
| `select`                   | `crossbeam::select!`, `tokio::select!`   |
| `go test -race`            | the compiler                             |
| worker pool                | `rayon`                                  |

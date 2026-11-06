# Appendix A: Phrasebook {.unnumbered}

Quick translations of common Go constructs. "≈" marks an approximation.

### Declarations {-}

| Go                                  | Rust                                     |
|-------------------------------------|------------------------------------------|
| `x := 1`                            | `let x = 1;`                             |
| `var x int` (zero value)            | `let x: i32 = 0;` (explicit)             |
| `x = 2` (reassign)                  | `let mut x = 1; x = 2;`                  |
| `const N = 10`                      | `const N: usize = 10;`                   |
| `type ID int64`                     | `struct Id(i64);`                        |
| `type Alias = T`                    | `type Alias = T;`                        |
| `var global = ...`                  | `static GLOBAL: T = ...;`                |
| `func f(a int) (int, error)`        | `fn f(a: i32) -> Result<i32, E>`         |
| `func (s *S) M()`                   | `impl S { fn m(&mut self) {} }`          |
| `func NewS() *S`                    | `fn new() -> Self`                       |
| `go:embed file.txt`                 | `include_str!("file.txt")`               |

### Types {-}

| Go                    | Rust                                     |
|-----------------------|------------------------------------------|
| `string`              | `String` (owned), `&str` (borrowed)      |
| `[]byte`              | `Vec<u8>`, `&[u8]`                       |
| `[]T`                 | `Vec<T>` (owned), `&[T]` / `&mut [T]`    |
| `[N]T`                | `[T; N]`                                 |
| `map[K]V`             | `HashMap<K, V>`, `BTreeMap<K, V>`        |
| `map[T]struct{}`      | `HashSet<T>`                             |
| `*T` (maybe nil)      | `Option<Box<T>>`, `Option<&T>`           |
| `*T` (shared, mutated)| `&mut T`, `Rc<RefCell<T>>`, `Arc<Mutex<T>>` |
| `interface{ M() }`    | `trait Tr { fn m(&self); }`              |
| interface value       | `Box<dyn Tr>`, `&dyn Tr`                 |
| `any`                 | generics, an `enum`, or `Box<dyn Any>`   |
| `error`               | `Box<dyn Error>`, `anyhow::Error`, an enum |
| `func(int) int`       | `fn(i32) -> i32`, `impl Fn(i32) -> i32`  |
| `chan T`              | `mpsc::Sender<T>` + `Receiver<T>`        |
| `struct{}`            | `()` or a unit struct                    |
| `[T any]`             | `<T>`                                    |
| `[T comparable]`      | `<T: Eq + Hash>`                         |
| `[T cmp.Ordered]`     | `<T: Ord>`                               |

### Control flow {-}

| Go                                  | Rust                                     |
|-------------------------------------|------------------------------------------|
| `for i := 0; i < n; i++`            | `for i in 0..n`                          |
| `for i, v := range s`               | `for (i, v) in s.iter().enumerate()`     |
| `for k, v := range m`               | `for (k, v) in &m`                       |
| `for {}`                            | `loop {}`                                |
| `for cond {}`                       | `while cond {}`                          |
| `switch x { case 1, 2: }`           | <code>match x { 1 &#124; 2 => .., _ => .. }</code>      |
| `switch v := x.(type)`              | `match` on an enum                       |
| `if v, ok := m[k]; ok`              | `if let Some(v) = m.get(&k)`             |
| `if err != nil { return err }`      | `?`                                      |
| `cond ? a : b` (n/a in Go)          | `if cond { a } else { b }`               |
| `defer f()`                         | `Drop` / scope guard                     |
| `panic(x)` / `recover()`            | `panic!(..)` / `catch_unwind` (rare)     |
| `goto`                              | labeled `break` / `continue`            |

### Common operations {-}

| Go                                  | Rust                                     |
|-------------------------------------|------------------------------------------|
| `len(s)`                            | `s.len()`                                |
| `append(s, x)`                      | `v.push(x)`                              |
| `append(a, b...)`                   | `a.extend_from_slice(&b)`                |
| `copy(dst, src)`                    | `dst.copy_from_slice(src)`               |
| `s[a:b]`                            | `&s[a..b]`                               |
| `make([]T, n)`                      | `vec![T::default(); n]`                  |
| `make([]T, 0, n)`                   | `Vec::with_capacity(n)`                  |
| `m[k] = v`                          | `m.insert(k, v);`                        |
| `delete(m, k)`                      | `m.remove(&k);`                          |
| `sort.Slice(s, less)`               | <code>s.sort_by(&#124;a, b&#124; a.x.cmp(&amp;b.x))</code>      |
| `slices.Sort(s)`                    | `s.sort()` / `s.sort_unstable()`         |
| `slices.Contains(s, x)`             | `s.contains(&x)`                         |
| `slices.Reverse(s)`                 | `s.reverse()`                            |
| `slices.Max(s)`                     | `s.iter().max()`                         |
| `maps.Keys(m)`                      | `m.keys()`                               |
| `new(T)`                            | `Box::new(T::default())`                 |
| `&T{...}`                           | `T { .. }` (or `Box::new(T { .. })`)     |
| `x.(T)`                             | `match` / `downcast_ref::<T>()`          |
| `errors.New("x")`                   | `anyhow!("x")` or an enum variant        |
| `fmt.Errorf("ctx: %w", err)`        | `.context("ctx")?`                       |
| `errors.Is(err, ErrX)`              | `matches!(e, E::X)`                      |
| `os.Exit(1)`                        | `std::process::exit(1)`                  |
| `os.Args`                           | `std::env::args()`                       |
| `os.Getenv("K")`                    | `std::env::var("K")` → `Result`          |
| `time.Now()`                        | `Instant::now()` / `SystemTime::now()`   |
| `time.Since(t)`                     | `t.elapsed()`                            |
| `time.Sleep(d)`                     | `thread::sleep(d)` / `tokio::time::sleep(d).await` |

### Concurrency {-}

| Go                                  | Rust                                     |
|-------------------------------------|------------------------------------------|
| `go f()`                            | `thread::spawn(f)` / `tokio::spawn(fut)` |
| `ch := make(chan T, n)`             | `let (tx, rx) = mpsc::sync_channel(n);`  |
| `ch <- v`                           | `tx.send(v)`                             |
| `v := <-ch`                         | `rx.recv()`                              |
| `v, ok := <-ch`                     | `match rx.recv() { Ok(v) .., Err(_) .. }`|
| `close(ch)`                         | `drop(tx)`                               |
| `for v := range ch`                 | `for v in rx`                            |
| `select { ... }`                    | `tokio::select! { ... }`                 |
| `mu.Lock(); defer mu.Unlock()`      | `let g = m.lock().unwrap();`             |
| `wg.Add/Done/Wait`                  | `JoinHandle::join`, `thread::scope`      |
| `ctx, cancel := WithTimeout(..)`    | `tokio::time::timeout(d, fut)`           |
| `atomic.AddInt64(&n, 1)`            | `n.fetch_add(1, Ordering::Relaxed)`      |
| `sync.Once`                         | `OnceLock` / `LazyLock`                  |

### Tooling {-}

| Go                                  | Rust                                     |
|-------------------------------------|------------------------------------------|
| `go mod tidy`                       | (automatic) / `cargo machete`            |
| `go vet`                            | `cargo clippy`                           |
| `go test -race`                     | the compiler; Miri / loom for `unsafe`   |
| `go test -bench`                    | `cargo bench` with criterion / divan     |
| `go test -cover`                    | `cargo llvm-cov` / `cargo tarpaulin`     |
| `go generate`                       | `build.rs` or proc macros                |
| `pprof`                             | `perf`, `cargo flamegraph`, `samply`     |
| `go build -ldflags "-s -w"`         | `strip = true` in profile                |
| `govulncheck`                       | `cargo audit` / `cargo deny`             |
| `GOFLAGS=-tags=x`                   | `--features x`                           |

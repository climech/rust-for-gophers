# Closures and Iterators

## Closures

```go
add := func(a, b int) int { return a + b }
```

```rust
let add = |a: i32, b: i32| a + b;
let add = |a, b| a + b;          // types usually inferred
let greet = |name: &str| {
    let msg = format!("hi {name}");
    println!("{msg}");
};
```

In Go, a closure captures variables **by reference**, and the GC keeps them
alive as long as the closure is. A Rust closure has to fit into the
ownership system, so each captured variable is captured in the least
demanding way that works:

- by shared reference (`&x`), if the body only reads `x`;
- by mutable reference (`&mut x`), if it modifies `x`;
- by value (move), if it consumes `x`.

The `move` keyword makes a closure take **ownership** of everything it
captures:

```rust
let name = String::from("ann");
let greet = move || println!("hi {name}"); // name moved into closure
// name is no longer usable here
std::thread::spawn(greet);                 // ok: closure is 'static
```

You need `move` whenever the closure outlives the current scope: threads,
async tasks, closures returned from functions, callbacks you store. In
practice that means almost everywhere Go would launch a goroutine with
`go func() {…}()`.

::: go
Go 1.22 fixed the loop-variable capture bug by giving each iteration a
fresh variable. Rust never had that bug: a closure that borrowed the loop
variable couldn't outlive the iteration, and a `move` closure gets its own
copy.
:::

### `Fn`, `FnMut`, `FnOnce`

Every closure has its own unique, anonymous type, so you can't name a
closure's type. Instead, closures implement one or more of three traits,
depending on what they do with their captures:

| Trait    | Can be called   | Body may…                         |
|----------|-----------------|-----------------------------------|
| `Fn`     | many times, even concurrently | only read captures  |
| `FnMut`  | many times, needs `&mut`      | mutate captures     |
| `FnOnce` | once                          | consume captures    |

Every `Fn` is also `FnMut`, and every `FnMut` is also `FnOnce`. Functions
that accept closures use the least restrictive bound they can:

```rust
fn apply_twice<F: Fn(i32) -> i32>(f: F, x: i32) -> i32 { f(f(x)) }

fn repeat<F: FnMut()>(n: usize, mut f: F) {
    for _ in 0..n { f(); }
}

let mut count = 0;
repeat(3, || count += 1);    // FnMut: mutates `count`
println!("{count}");         // 3

fn run_later(f: impl FnOnce() + Send + 'static) { /* ... */ }
```

Storing or returning closures follows the rules from Chapter 8:

```rust
fn make_adder(n: i32) -> impl Fn(i32) -> i32 {
    move |x| x + n
}

// Heterogeneous storage needs a trait object:
let handlers: Vec<Box<dyn Fn(&Request) -> Response>> = vec![
    Box::new(index),          // plain functions work too
    Box::new(move |r| not_found(r, &path)),
];
```

Plain function pointers have a type you can name, `fn(i32) -> i32`
(lowercase `fn`). Closures that capture nothing coerce to it.

## Iterators

An iterator is anything that implements `Iterator`. It has one required
method, `next(&mut self) -> Option<Item>`, plus dozens of provided
**adapters**. Go 1.23's range-over-func iterators (`iter.Seq[T]`) are
*push* iterators: the sequence calls your loop body. Rust iterators are
*pull* iterators: the consumer calls `next()`. Pull iterators compose
easily: you can zip two of them, stop early, or step through by hand.

```rust
let names: Vec<String> = users
    .iter()                              // Iterator<Item = &User>
    .filter(|u| u.active)
    .map(|u| u.name.to_uppercase())
    .take(10)
    .collect();
```

Three things to know:

**Iterators are lazy.** The adapters (`map`, `filter`, `take`, …) do nothing
on their own. Work happens when a *consumer* pulls items: `collect`,
`sum`, `count`, `for_each`, `fold`, `find`, `any`, `max_by_key`, or a
`for` loop. Calling `map` and dropping the result does nothing, and the
compiler warns about it.

**Iterators are zero-cost.** After monomorphisation and inlining, the chain
above compiles to roughly the same loop you'd write by hand, often with
bounds checks removed and sometimes vectorised. Go's `slices` and `maps`
helpers plus range-over-func offer similar ergonomics, but the closures
aren't always inlined.

**The three `iter` methods follow ownership.** `iter()` yields `&T`,
`iter_mut()` yields `&mut T`, `into_iter()` yields `T` and consumes the
collection.

### The adapters you'll use most

```rust
xs.iter().map(f)                // transform
xs.iter().filter(|x| p(x))      // keep matching
xs.iter().filter_map(|x| x.ok())// map + drop Nones in one go
xs.iter().flat_map(|x| x.children.iter())
xs.iter().enumerate()           // (index, item)
xs.iter().zip(ys.iter())        // pairs
xs.iter().rev()                 // backwards
xs.iter().skip(2).step_by(3)
xs.iter().take_while(|x| **x < 10)
xs.iter().chain(ys.iter())
xs.windows(2)  xs.chunks(64)    // slice methods: overlapping / not
xs.iter().peekable()            // look ahead without consuming
xs.iter().copied()  .cloned()   // &T -> T
```

### Consumers

```rust
let total: i64 = xs.iter().sum();
let n = xs.iter().filter(|x| x.ok).count();
let first_big = xs.iter().find(|x| x.size > 100);   // Option<&T>
let any_bad = xs.iter().any(|x| x.bad);
let oldest = users.iter().max_by_key(|u| u.age);    // Option<&User>
let csv = names.join(",");                          // on slices of str
let product = xs.iter().fold(1, |acc, x| acc * x);
```

`collect` is generic over its output. The target type, given by an
annotation or turbofish, decides what gets built:

```rust
let v: Vec<_> = it.collect();
let s: HashSet<_> = it.collect();
let m: HashMap<_, _> = pairs.into_iter().collect();
let text: String = chars.into_iter().collect();
let all: Result<Vec<_>, _> = strs.iter().map(|s| s.parse::<i32>())
                                  .collect();
let v = it.collect::<Vec<_>>();     // "turbofish" syntax
```

The `Result` case is especially useful: it collects into
`Ok(Vec)` if every element is `Ok`, and stops at the first `Err`.

### Writing your own iterator

Implement `next` (Chapter 8 showed `Countdown`). For one-off cases,
`std::iter::from_fn` builds an iterator from a closure, and
`std::iter::successors` from a seed and a step function:

```rust
let mut state = (0u64, 1u64);
let fib = std::iter::from_fn(move || {
    let r = state.0;
    state = (state.1, state.0 + state.1);
    Some(r)
});
let first10: Vec<u64> = fib.take(10).collect();

let powers = std::iter::successors(Some(1u32), |x| x.checked_mul(2));
```

To let callers write `for x in &my_type`, implement `IntoIterator` for
`&MyType`. Usually this just delegates to an inner `Vec`'s `iter()`.

::: note
Should you use a loop or an iterator chain? Both are idiomatic. Chains
suit transformations: map, filter, collect. Loops suit complex control flow
or many side effects. A chain that needs `?` inside a closure, or
early-returns from the outer function, is usually clearer as a loop.
:::

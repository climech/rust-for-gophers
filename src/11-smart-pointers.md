# Smart Pointers and Interior Mutability

In Go, `*T` does everything: it shares, it mutates, it keeps a value
alive, and it can point into the middle of a struct. Rust splits those
roles across several types, each with its own costs and guarantees. This
chapter covers that toolbox and when to use each piece.

| You want…                              | Use                       |
|----------------------------------------|---------------------------|
| a single owner, data on the heap       | `Box<T>`                  |
| shared ownership, one thread           | `Rc<T>`                   |
| shared ownership, across threads       | `Arc<T>`                  |
| to mutate through a shared reference, one thread | `Cell<T>`, `RefCell<T>` |
| to mutate shared data across threads   | `Mutex<T>`, `RwLock<T>`, atomics |
| one-time lazy initialisation           | `OnceCell`, `OnceLock`, `LazyLock` |
| a non-owning back-reference            | `Weak<T>`                 |
| to borrow or own, decided at runtime   | `Cow<'a, T>`              |

## `Box<T>`

`Box<T>` puts a value on the heap and owns it. Dropping the box frees the
allocation. It's a single pointer with no overhead. You use it in three
situations:

```rust
// 1. Recursive types (otherwise the size would be infinite)
enum Expr {
    Num(f64),
    Add(Box<Expr>, Box<Expr>),
    Neg(Box<Expr>),
}

// 2. Trait objects
let handler: Box<dyn Fn(u32) -> u32> = Box::new(|x| x + 1);

// 3. Moving a large value around cheaply, or keeping a stable address
let big = Box::new([0u8; 1 << 20]);
```

Go does all of this with an ordinary pointer, and escape analysis decides
whether the allocation goes on the heap. Rust makes heap allocation an
explicit, visible decision.

## `Rc<T>` and `Arc<T>`: shared ownership

When a value really has several owners, and no single one of them
naturally outlives the others, use reference counting:

```rust
use std::rc::Rc;

let config = Rc::new(Config::load());
let a = Service::new(Rc::clone(&config));  // count = 2
let b = Service::new(Rc::clone(&config));  // count = 3
// Config is freed when the last Rc is dropped.
```

`Rc::clone` copies a pointer and increments a counter. It doesn't copy
the `Config`. Writing `Rc::clone(&x)` rather than `x.clone()` makes it
clear that the clone is cheap.

`Rc` isn't thread-safe because its counter isn't atomic, and the compiler
won't let it cross threads (Chapter 13). **`Arc<T>`** ("atomically
reference counted") is the thread-safe version, a little slower because
of the atomic operations. Use `Arc` for anything shared between threads or
async tasks.

The important restriction: **`Rc<T>` and `Arc<T>` give only shared (`&T`)
access.** Shared XOR mutable still applies, so on its own an `Arc<T>` is
read-only. To mutate, combine it with interior mutability.

::: go
A Go pointer that several goroutines share is roughly an
`Arc<Mutex<T>>`, except that Go doesn't make you use the `Mutex`. Rust
makes you choose. A plain `Arc<T>` is immutable sharing and needs no lock.
If you need mutation, the lock is part of the type, and you can't reach the
data without taking it.
:::

## Interior mutability

Some designs really do need to mutate data that is shared: a cache inside
a `&self` method, a counter shared by callbacks, a graph node updated by
its neighbours. **Interior mutability** types allow mutation through a
shared reference by moving the aliasing check from compile time to runtime,
or by making the operation atomic.

### `Cell<T>`

`Cell<T>` is for `Copy` types on a single thread. You `get` and `set`
whole values and never borrow the inside, so nothing can alias:

```rust
use std::cell::Cell;

struct Stats { hits: Cell<u64> }

impl Stats {
    fn record(&self) {               // &self, yet mutates
        self.hits.set(self.hits.get() + 1);
    }
}
```

### `RefCell<T>`

`RefCell<T>` applies the borrow rules **at runtime**. `borrow()` returns a
shared guard and `borrow_mut()` an exclusive one. Breaking the rules, for
example calling `borrow_mut()` while a `borrow()` guard is still alive,
**panics**.

```rust
use std::cell::RefCell;
use std::rc::Rc;

let log = Rc::new(RefCell::new(Vec::<String>::new()));

let log2 = Rc::clone(&log);
let on_event = move |e: &str| log2.borrow_mut().push(e.to_string());

on_event("start");
on_event("stop");
println!("{:?}", log.borrow()); // ["start", "stop"]
```

`Rc<RefCell<T>>` is the single-threaded "shared mutable object" and the
closest thing to a Go pointer to a struct. Its thread-safe counterpart is
`Arc<Mutex<T>>` (or `Arc<RwLock<T>>`).

::: warn
`RefCell` doesn't remove the borrow rules. It turns violations into
panics. Keep guards short-lived (`cell.borrow_mut().push(x)` on one line),
and don't hold one across a call that might borrow the same cell again. If
your code is full of `Rc<RefCell<…>>`, consider whether a design with
clearer ownership would be simpler.
:::

### Lazy and one-time initialisation

```rust
use std::sync::LazyLock;
use regex::Regex;

static EMAIL: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[^@]+@[^@]+$").unwrap());

fn valid(s: &str) -> bool { EMAIL.is_match(s) }
```

`LazyLock` is Go's `sync.OnceValue`, and `OnceLock` is `sync.Once` plus the
value it guards. `OnceCell` and `LazyCell` are the single-threaded
versions.

## Cycles and `Weak<T>`

Reference counting can't free cycles. If two `Rc`s point at each other,
neither count ever reaches zero, and both values **leak**. Leaks are memory
*safe* in Rust, but you still don't want them. Go's tracing GC handles
cycles; Rust's reference counting doesn't.

`Weak<T>` is a non-owning pointer that doesn't keep the value alive. You
call `upgrade()`, which returns an `Option<Rc<T>>`, to get access. The
usual shape is a tree where parents own their children and children hold a
weak pointer back to the parent:

```rust
use std::rc::{Rc, Weak};
use std::cell::RefCell;

struct Node {
    value: i32,
    parent: RefCell<Weak<Node>>,
    children: RefCell<Vec<Rc<Node>>>,
}
```

## Graphs: use indices

Graph-shaped data with arbitrary edges is where Go's GC is most
convenient, and where `Rc<RefCell<Node>>` code is at its worst. The
idiomatic Rust approach is to **store nodes in a `Vec` and refer to them by
index**:

```rust
struct Graph {
    nodes: Vec<Node>,
}

struct Node {
    name: String,
    edges: Vec<usize>,     // indices into Graph::nodes
}

impl Graph {
    fn add(&mut self, name: &str) -> usize {
        self.nodes.push(Node { name: name.into(), edges: vec![] });
        self.nodes.len() - 1
    }
    fn link(&mut self, a: usize, b: usize) {
        self.nodes[a].edges.push(b);
    }
}
```

The borrow checker is happy because the `Graph` owns every node and edges
are plain integers. It's also cache-friendly. The risk is stale indices
after a removal, which crates like `slotmap` (generational indices) and
`petgraph` handle. This **arena pattern** is everywhere in Rust: compilers,
ECS game engines, DOM implementations.

## `Cow`: borrow or own

`Cow<'a, B>` ("clone on write") holds either a borrowed reference or an
owned value. It's useful for functions that usually return their input
unchanged but sometimes need to allocate:

```rust
use std::borrow::Cow;

fn normalize(s: &str) -> Cow<'_, str> {
    if s.contains('\t') {
        Cow::Owned(s.replace('\t', "    "))  // allocate only if needed
    } else {
        Cow::Borrowed(s)
    }
}
```

`Cow<str>` dereferences to `&str`, so callers mostly don't care which one
they got.

## `Deref` and deref coercion

Smart pointers implement `Deref`, so `*boxed` gives you the inner value,
method calls pass straight through, and the compiler inserts
conversions automatically where types require it:

```rust
fn takes_str(s: &str) {}

let s = String::from("x");
let b = Box::new(String::from("y"));
let r = Rc::new(String::from("z"));
takes_str(&s);  // &String     -> &str
takes_str(&b);  // &Box<String> -> &String -> &str
takes_str(&r);  // &Rc<String>  -> &String -> &str
```

This chain of conversions is **deref coercion**. It's why `&String` passes
for `&str` and `&Vec<T>` for `&[T]`.

::: warn
Don't use `Deref` to imitate Go struct embedding (`impl Deref for Wrapper
{ Target = Inner }`) so that a wrapper "inherits" the inner type's methods.
It works, but it's considered an anti-pattern: it confuses readers, and
trait implementations don't come along with it. Forward the methods you
need explicitly, or expose the inner value.
:::

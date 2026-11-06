# Structs, Enums and Pattern Matching

## Structs

Structs look much like Go's:

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct User {
    pub id: u64,
    pub name: String,
    email: Option<String>, // private field
}

let name = String::from("ann");
let u = User { id: 1, name, email: None }; // field init shorthand
let v = User { id: 2, ..u.clone() };       // struct update syntax
```

There are a few variants:

```rust
struct Meters(f64);          // tuple struct; access with .0
struct Point3(i32, i32, i32);
struct Marker;               // unit struct, zero-sized
```

A single-field tuple struct is the **newtype** pattern, the counterpart of
Go's `type UserID int64`. It creates a distinct type with no runtime cost.
Unlike in Go, a newtype doesn't inherit any methods or operators from the
wrapped type. You add what you need, usually through `derive`.

### No zero values

This is a significant difference. Go initializes every variable to a zero
value, so `var u User` is always valid, and "the zero value should be
useful" is a design goal. **Rust has no zero values.** Every field must be
initialized explicitly, and reading an uninitialized variable is a compile
error.

The upside is that a type can't end up half-constructed. A `User` always
has a name, and a `Mutex` is never accidentally copied in its zero state.
When a sensible default exists, the type implements the `Default` trait:

```rust
#[derive(Default)]
struct Options {
    retries: u32,       // 0
    verbose: bool,      // false
    tag: String,        // ""
}

let o = Options { retries: 3, ..Default::default() };
```

Constructors are plain associated functions, by convention named `new`, or
`with_…` / `from_…` for variants. Unlike Go's `NewUser` functions, they're
defined in the type's `impl` block and called as `User::new(…)`. Because
private fields can only be set inside the module, a private field plus a
constructor gives you a guaranteed-valid type.

## Enums are sum types

Go's `iota` constants are just named integers:

```go
type State int
const (
    Idle State = iota
    Running
    Done
)
```

Rust enums can be used the same way, but each variant can also **carry
its own data**:

```rust
enum Shape {
    Circle { radius: f64 },
    Rect { w: f64, h: f64 },
    Triangle(f64, f64, f64),
    Empty,
}
```

A value of type `Shape` is exactly one of these variants. The compiler
stores a small tag recording which variant it is, alongside room for the
largest variant's data. It isn't a pointer to an object on the heap.

In Go you'd model this with an interface and a type switch:

```go
type Shape interface{ isShape() }
type Circle struct{ Radius float64 }
type Rect struct{ W, H float64 }
func (Circle) isShape() {}
func (Rect) isShape()   {}

switch s := shape.(type) {
case Circle: ...
case Rect: ...
} // forgot a case? the compiler doesn't care
```

The Rust version is checked for **exhaustiveness**:

```rust
fn area(s: &Shape) -> f64 {
    match s {
        Shape::Circle { radius } => 3.14159 * radius * radius,
        Shape::Rect { w, h } => w * h,
        Shape::Triangle(a, b, c) => {
            let p = (a + b + c) / 2.0;
            (p * (p - a) * (p - b) * (p - c)).sqrt()
        }
        Shape::Empty => 0.0,
    }
}
```

Add a variant and every `match` that doesn't handle it stops compiling.
This turns out to be one of Rust's most useful features. You can make a
large refactor, follow the compiler errors, and when they're gone the
change is complete.

::: go
Enums can't be extended outside their crate, while interfaces are open to
anyone. That's the trade-off. Use an enum when you have a **closed set of
variants**: states, AST nodes, messages, results. Use a trait (Chapter 8)
when you want an **open set** that others can extend. Go only gives you
the open option, so you emulate closed sets with unexported marker
methods and hope everyone writes a `default:` case.
:::

Enums can have methods, just like structs:

```rust
impl Shape {
    fn is_empty(&self) -> bool { matches!(self, Shape::Empty) }
}
```

### Make illegal states unrepresentable

A common Go struct:

```go
type Conn struct {
    State     string    // "disconnected", "connecting", "connected"
    Addr      string    // set when connecting or connected
    SessionID string    // only valid when connected
    Retries   int       // only meaningful when connecting
}
```

Nothing stops `SessionID` from being set while disconnected. In Rust you
put each piece of data in the state it belongs to:

```rust
enum Conn {
    Disconnected,
    Connecting { addr: String, retries: u32 },
    Connected { addr: String, session_id: String },
}
```

Now it's impossible to read a session ID from a connection that doesn't
have one, and nothing needs to be checked at runtime.

## Pattern matching

`match` is much more capable than Go's `switch`. Patterns can destructure
nested data, bind variables, match ranges and have guards:

```rust
match msg {
    Msg::Move { x: 0, y } => println!("on the y axis at {y}"),
    Msg::Move { x, y } if x == y => println!("diagonal"),
    Msg::Move { .. } => println!("somewhere else"),
    Msg::Write(text) => println!("{text}"),
    Msg::Color(r, _, _) if r > 200 => println!("reddish"),
    Msg::Color(..) => {}
    Msg::Quit => return,
}

match code {
    200..=299 => "ok",
    301 | 302 | 307 | 308 => "redirect",
    n @ 400..=499 => { log(n); "client error" }
    _ => "other",
}
```

`match` is an expression, all arms must have the same type, and there is no
fallthrough, so there's no `break` to forget and no `fallthrough` keyword.

Patterns also work in `let`, function parameters and `for` loops:

```rust
let (q, r) = divmod(17, 5);
let User { name, id, .. } = user;   // destructure a struct
for (k, v) in &map { }
fn dist(&(x, y): &(f64, f64)) -> f64 { (x * x + y * y).sqrt() }
```

When matching on a reference, bindings automatically become references
too. Matching `&Shape` gives you `radius: &f64`. This "match ergonomics"
feature is why the `area` function above works without any `&` or `*`.

### Shorthand forms

```rust
if let Shape::Circle { radius } = s {
    println!("circle of radius {radius}");
}

// let-else: bind or bail out. Great for early returns.
let Some(user) = find_user(id) else {
    return Err(Error::NotFound);
};

while let Some(job) = queue.pop() { run(job); }

let is_big = matches!(s, Shape::Rect { w, .. } if *w > 100.0);
```

`let … else` corresponds to Go's guard clause, `if x == nil { return }`,
except that afterwards `user` is a plain, unwrapped value.

Conditions can be chained with `&&` inside `if let` (stable since Rust
1.88, in the 2024 edition):

```rust
if let Some(u) = user && u.is_admin() && let Some(t) = u.token() {
    authorize(t);
}
```

## `Option`: no more nil

Rust has no null. The possibility of a missing value is part of the type:

```rust
enum Option<T> {
    Some(T),
    None,
}
```

`Option` is an ordinary enum from the standard library. `Some` and `None`
are in scope everywhere. A function that might not find something returns
`Option<T>`, and the caller can't use the result without handling `None`:

```rust
fn find(users: &[User], id: u64) -> Option<&User> {
    users.iter().find(|u| u.id == id)
}

match find(&users, 7) {
    Some(u) => println!("{}", u.name),
    None => println!("no such user"),
}
```

Compare this with Go, where a `*User` may or may not be nil and only the
documentation tells you which, or where you return `(User, bool)`.
`Option` also removes the need for Go's "comma ok" idiom, since
`map.get(&k)` returns an `Option<&V>`.

`Option` comes with a large set of combinators. These are the ones you'll
use daily:

```rust
let name: Option<&str> = user.map(|u| u.name.as_str());
let name = name.unwrap_or("anonymous");
let len = maybe_s.as_deref().map_or(0, str::len);
let port: u16 = env_port.and_then(|p| p.parse().ok()).unwrap_or(8080);
let user = find(&users, id).ok_or(Error::NotFound)?; // into Result
let x = slot.take();       // move out, leave None behind
let v = cache.get_or_insert_with(compute);
```

`unwrap()` extracts the value and **panics** on `None`. `expect("msg")` does
the same with a message. Use them in tests, in prototypes, and where `None`
would be a bug, i.e. an invariant you've already established. In library
code, propagate instead (next chapter).

::: note
`Option<&T>`, `Option<Box<T>>` and `Option<NonZeroU32>` are the same size
as the bare pointer or integer. The compiler uses the forbidden null (or
zero) value to represent `None`. Using `Option` adds no overhead compared
with a nullable pointer.
:::

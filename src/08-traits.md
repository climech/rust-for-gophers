# Traits and Generics

Traits are Rust's version of interfaces, and they do considerably more:
they constrain generics, provide operator overloading, drive
`derive`, and mark thread-safety. This is the second largest conceptual
step after ownership.

## Defining and implementing traits

```rust
pub trait Shape {
    fn area(&self) -> f64;
    fn name(&self) -> String {          // default method
        String::from("shape")
    }
}

struct Square(f64);

impl Shape for Square {
    fn area(&self) -> f64 { self.0 * self.0 }
    // name() uses the default
}
```

### Nominal, not structural

The first difference from Go: implementation is **explicit**. In Go, a type
satisfies an interface just by having the right methods. In Rust, you write
`impl Trait for Type`, and methods in a type's own `impl` block are not
trait methods, even if their names and signatures match.

There are trade-offs both ways. Go's structural typing lets you define an
interface in the consumer package after the fact, which Rust can't do. In
return, Rust lets you implement a trait for a type you didn't write:

```rust
trait Shout { fn shout(&self) -> String; }

impl Shout for str {
    fn shout(&self) -> String { self.to_uppercase() + "!" }
}

"hello".shout(); // "HELLO!"
```

That's impossible in Go, where you can only declare methods on types in
your own package. The limit in Rust is the **orphan rule**: you can
implement a trait for a type only if your crate defines either the trait
or the type. It stops two crates from providing conflicting
implementations. To implement a foreign trait for a foreign type, wrap
the type in a newtype.

Calling a trait method requires the trait to be **in scope**. If the
compiler says "no method named `write_all` found", you probably need
`use std::io::Write;`.

## Generics

```rust
fn largest<T: PartialOrd>(items: &[T]) -> Option<&T> {
    let mut best = items.first()?;
    for it in items {
        if it > best { best = it; }
    }
    Some(best)
}
```

```go
func Largest[T cmp.Ordered](items []T) (T, bool) { ... }
```

They look similar, but there are important differences:

| Go generics                           | Rust generics                    |
|---------------------------------------|----------------------------------|
| constraints are interfaces/type sets  | bounds are traits                |
| <code>~int &#124; ~float64</code> type sets | no union types; use a trait      |
| no generic methods                    | generic methods are fine         |
| GC-shape stenciling (partly boxed)    | full monomorphization            |
| operators via `cmp.Ordered` etc.      | operators via traits (`Add`, `PartialOrd`) |
| type inference: function args         | inference across the whole body  |

**Monomorphization** means the compiler generates a separate copy of
`largest` for each concrete `T` it's used with, and optimizes each copy as
if you'd written it by hand. Generic Rust code is therefore as fast as
specialized code. You pay in compile time and binary size. Go's
implementation shares one copy among all pointer types and passes a
dictionary, which compiles faster but can be slower at runtime.

When bounds grow, a `where` clause keeps the signature readable:

```rust
fn summarize<K, V>(map: &HashMap<K, V>) -> String
where
    K: Display + Eq + Hash,
    V: Debug,
{
    // ...
}
```

Generic types work as you'd expect:

```rust
struct Stack<T> { items: Vec<T> }

impl<T> Stack<T> {
    fn push(&mut self, t: T) { self.items.push(t); }
    fn pop(&mut self) -> Option<T> { self.items.pop() }
}

// Methods that exist only when T meets extra bounds:
impl<T: Display> Stack<T> {
    fn render(&self) -> String {
        self.items.iter().map(|t| t.to_string())
            .collect::<Vec<_>>().join(", ")
    }
}
```

The second `impl` block, called a *conditional impl*, has no equivalent in
Go.

## Static vs dynamic dispatch

A Go interface value is always dynamic. It's a two-word pair of a type
descriptor (itab) and a data pointer, and calls go through a method
table. Rust lets you choose.

**Static dispatch** uses generics or `impl Trait`:

```rust
fn print_area(s: &impl Shape) {   // sugar for <S: Shape>(s: &S)
    println!("{}", s.area());
}

fn make_shape() -> impl Shape {    // "some type that implements Shape"
    Square(2.0)
}
```

`impl Trait` in return position hides the concrete type from the caller.
It's essential for returning closures and iterators, whose types can't be
written down. The function must still return **one** concrete type.

**Dynamic dispatch** uses **trait objects**, written `dyn Trait`:

```rust
let shapes: Vec<Box<dyn Shape>> = vec![
    Box::new(Square(1.0)),
    Box::new(Circle(2.0)),
];
for s in &shapes {
    println!("{}: {}", s.name(), s.area()); // vtable call
}
```

`dyn Shape` has no fixed size, so it always lives behind a pointer:
`&dyn Shape`, `Box<dyn Shape>` or `Arc<dyn Shape>`. Such a pointer is a
**fat pointer** (data pointer plus vtable pointer), the same layout as a
Go interface value.

::: go
`Box<dyn Trait>` is the closest thing to a Go interface value, and the
right tool when you need a heterogeneous collection or a plugin point
chosen at runtime. Most Rust code uses generics by default and switches to
`dyn` when it needs that runtime flexibility, or when monomorphization would
bloat the binary.
:::

Not every trait can be used as `dyn`. It must be **dyn-compatible**
(formerly "object safe"): methods can't be generic, and they can't return
`Self` by value. The reason is that the vtable has to be built ahead of
time, which isn't possible for an unbounded family of generic methods.
The compiler will tell you when you hit this.

Dynamic downcasting, Go's `v.(Concrete)`, is available through
`std::any::Any`, but it's rarely needed. If you find yourself wanting it,
an enum is usually the better design.

## Associated types and constants

A trait can declare types and constants that each implementation fills
in:

```rust
pub trait Iterator {
    type Item;
    fn next(&mut self) -> Option<Self::Item>;
    // ...plus ~75 provided methods: map, filter, sum, ...
}

struct Countdown(u32);

impl Iterator for Countdown {
    type Item = u32;
    fn next(&mut self) -> Option<u32> {
        if self.0 == 0 { return None; }
        self.0 -= 1;
        Some(self.0 + 1)
    }
}
```

The difference from a generic parameter (`trait Iterator<T>`) is that an
associated type is chosen once per implementation. `Countdown` is an
iterator of `u32`, period. Bounds can constrain it:
`fn total<I: Iterator<Item = u32>>(it: I)`.

## Supertraits and blanket impls

```rust
trait Entity: Debug + Clone {   // implementors must also be Debug+Clone
    fn id(&self) -> u64;
}

// Blanket impl: every type that implements Display gets ToString.
// (This is literally how std defines `to_string()`.)
impl<T: Display + ?Sized> ToString for T {
    fn to_string(&self) -> String { /* ... */ }
}
```

`?Sized` relaxes the implicit requirement that `T` has a known size, so the
impl also covers `str` and `dyn Trait`.

## The standard traits you need to know

Most of your types will `#[derive(...)]` a handful of these. A derive is
[compiler-generated]{.nobr} boilerplate, field by field.

| Trait              | Purpose                        | Go analog             |
|--------------------|--------------------------------|-------------------------|
| `Debug`            | `{:?}` formatting              | `%+v` (automatic in Go) |
| `Display`          | `{}` formatting, user-facing   | `String() string`       |
| `Clone`            | explicit `.clone()`            | manual copying          |
| `Copy`             | implicit bitwise copy          | value semantics         |
| `PartialEq`, `Eq`  | `==`                           | `comparable`            |
| `PartialOrd`, `Ord`| `<`, sorting                   | `cmp.Ordered`, `cmp.Compare` |
| `Hash`             | usable as a map key            | `comparable`            |
| `Default`          | `T::default()`                 | zero value              |
| `From`, `Into`     | infallible conversion          | conversion functions    |
| `TryFrom`, `TryInto` | fallible conversion          | functions returning error |
| `FromStr`          | `"42".parse::<T>()`            | `strconv.ParseX`        |
| `AsRef`, `Borrow`  | cheap reference conversion     | —                       |
| `Deref`            | `*x`, auto-deref to inner type | embedding (loosely)     |
| `Drop`             | destructor                     | `defer` / finalizers    |
| `Iterator`, `IntoIterator` | `for` loops            | range-over-func         |
| `Send`, `Sync`     | thread safety (Chapter 13)     | —                       |

A few notes:

- `PartialEq` vs `Eq` (and `PartialOrd` vs `Ord`) exists because of floats.
  `NaN != NaN`, so `f64` is only `PartialEq`. `HashMap` keys need `Eq +
  Hash`, which is why you can't key a map by `f64`. Go lets you do that
  and quietly gets it wrong for NaN.
- Implement `From<A> for B` and you get `Into<B> for A` for free. Accepting
  `impl Into<String>` lets callers pass either `&str` or `String`.
- Go prints any value with `%v` through reflection. Rust has no runtime
  reflection, so a type is printable only if it implements `Debug` or
  `Display`. Derive `Debug` on almost everything.

### Operator overloading

Operators are traits in `std::ops`:

```rust
use std::ops::Add;

#[derive(Debug, Clone, Copy, PartialEq)]
struct V2 { x: f64, y: f64 }

impl Add for V2 {
    type Output = V2;
    fn add(self, o: V2) -> V2 { V2 { x: self.x + o.x, y: self.y + o.y } }
}

let c = V2 { x: 1.0, y: 2.0 } + V2 { x: 0.5, y: 0.5 };
```

Go deliberately doesn't support this. Rust supports it but keeps it
restrained: there are no custom operators, and the set of overloadable
operators is fixed (`Add`, `Mul`, `Index`, `Neg`, `BitAnd`, …).

## Generics or trait objects?

- Default to **generics** (`impl Trait` / `<T: Trait>`): they're zero-cost,
  and the compiler knows the concrete type.
- Use **`dyn Trait`** for heterogeneous collections, for plugin points
  chosen at runtime, to cut compile times or binary size, or when a generic
  parameter would leak into many unrelated types.
- Use an **enum** when the set of types is closed and known up front. It is
  often better than both.

::: warn
Don't model Go-style "accept interfaces" by putting every dependency behind
`Box<dyn Trait>` by reflex. Abstraction in Rust has costs you can see in
the code: lifetime and `Send` bounds, dyn-compatibility rules, generic
parameters that spread. Abstract where you need a seam, for example for
testing or for swappable backends, and use concrete types elsewhere.
:::

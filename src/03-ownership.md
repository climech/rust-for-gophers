# Ownership

This chapter and the next two cover what makes Rust Rust. Nothing in Go
prepares you for them directly, but you already understand the underlying
problems. You just haven't had to state the solutions in your type
signatures before.

## The problem ownership solves

Every program that allocates memory has to decide when to free it. There are
three classic answers:

1. **The programmer frees it** (C, [C++]{.nobr}). Fast and predictable, but
   use-after-free, double-free and leaks are routine bugs, and many of them
   become security vulnerabilities.
2. **A garbage collector frees it** (Go, Java). Safe and convenient. You pay
   in runtime overhead, unpredictable pauses (small in modern Go, but not
   zero), higher memory use, and the need for a runtime.
3. **The compiler works out when to free it** (Rust). Every value has a
   single *owner*, and when the owner goes out of scope the value is freed.
   The compiler checks this statically, so there's no runtime cost and no
   dangling pointers.

Option 3 is only possible if the compiler can always tell who owns what.
That requirement is what makes the language feel different. Code that would
be harmless in Go, like two variables pointing to the same heap data, needs
to be spelled out in Rust.

## Stack, heap and Go's escape analysis

In Go, you rarely think about the stack and the heap. You write `&T{}`
anywhere, and escape analysis decides whether the value can live on the
stack or must be moved to the heap. If a pointer outlives its function,
the value escapes and the GC takes care of it.

Rust makes this explicit. Local values live on the stack by default. Heap
allocation happens through specific types: `Box<T>` for a single value,
`Vec<T>` for a growable array, `String` for growable text, and a few
others. These types are small handles on the stack (a pointer, plus length
and capacity for `Vec` and `String`) that own a heap buffer. That layout is
exactly the same as a Go slice header. The difference is what happens when
you copy the handle.

## The rules

1. Each value has exactly one **owner**, a variable or a field.
2. When the owner goes out of scope, the value is **dropped** (freed).
3. Ownership can be **moved** to a new owner. After a move, the old owner
   can no longer be used.

## Moves

```go
a := []int{1, 2, 3}
b := a        // copies the slice header; a and b share the array
b[0] = 99
fmt.Println(a[0]) // 99. Aliasing, which is sometimes surprising
```

```rust
let a = vec![1, 2, 3];
let b = a;          // ownership of the heap buffer MOVES to b
println!("{:?}", a); // error[E0382]: borrow of moved value: `a`
```

The bytes copied are the same in both languages: pointer, length and
capacity. What differs is that Rust **invalidates the source**. If both
`a` and `b` were usable, both would try to free the same buffer when
they went out of scope (a double free), or one would see changes made by
the other (aliasing). The move rule rules out both.

Passing an argument to a function is also a move:

```rust
fn consume(v: Vec<i32>) {
    println!("{}", v.len());
} // v dropped here, buffer freed

fn main() {
    let data = vec![1, 2, 3];
    consume(data);
    consume(data); // error: use of moved value
}
```

So is returning a value, which moves ownership out to the caller:

```rust
fn make() -> Vec<i32> {
    let v = vec![1, 2, 3];
    v // moved to the caller; NOT freed here
}
```

In Go you'd be returning a slice and the GC would keep the array alive. In
Rust, the move tells the compiler that responsibility for freeing the buffer
has passed to the caller.

::: key
A move is a shallow bitwise copy followed by the compiler forgetting the
source. It costs no more than copying a Go slice header. Moves never copy
heap data.
:::

The compiler tracks moves along every control-flow path:

```rust
let s = String::from("hi");
if cond {
    drop(s); // moved into drop() on this path
}
println!("{s}"); // error: value used after being moved
                 // (on at least one path)
```

## `Copy` types

Not everything moves. Integers, floats, `bool`, `char`, and tuples or
arrays made only of these, are `Copy`: assigning them copies the bits and
leaves the original usable, as you'd expect.

```rust
let x = 5;
let y = x;
println!("{x} {y}"); // fine: i32 is Copy
```

A type can be `Copy` only if a bitwise copy is a complete, independent
duplicate. That means it owns no heap memory or other resources. Your own
structs can opt in with `#[derive(Clone, Copy)]` (Chapter 8) when all their
fields are `Copy`.

## `Clone`: explicit deep copies

When you really do want two independent copies of heap data, ask for one:

```rust
let a = vec![1, 2, 3];
let b = a.clone(); // allocates a new buffer and copies elements
println!("{a:?} {b:?}");
```

Go has no single equivalent. You'd write `slices.Clone(a)`, `maps.Clone(m)`,
or copy fields by hand, and a "deep copy" of a struct holding pointers isn't
well defined. In Rust, `.clone()` is a method from the `Clone` trait, and
each type defines what cloning means for it.

Because cloning is explicit, allocations are visible in the code. When you
see `.clone()` in a hot loop, you know there's a cost there.

::: note
Beginners often add `.clone()` until the compiler stops complaining. That's
fine while you're learning: correct code that clones a little too much is
better than code that doesn't compile. Once the ownership model feels
familiar, most of those clones turn into borrows (next chapter).
:::

## Drop: deterministic destruction

When an owner goes out of scope, Rust calls the value's destructor right
away, deterministically, in reverse order of declaration. Types customize
this by implementing the `Drop` trait:

```rust
struct TempFile { path: String }

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

fn work() {
    let tmp = TempFile { path: "/tmp/x".into() };
    // ... use tmp ...
} // tmp.drop() runs here, on every exit path, including panics
```

This pattern is known as **RAII** (Resource Acquisition Is
Initialization). It's how Rust closes files, releases locks, closes
sockets and commits or rolls back transactions. There's usually no need for
a `defer`-like construct:

```go
f, err := os.Open(path)
if err != nil { return err }
defer f.Close()
```

```rust
let f = File::open(path)?; // closed automatically when `f` is dropped
```

::: go
`defer` is tied to the *function*, while `Drop` is tied to the *value*.
That means:

- You can't forget to clean up. There's no `defer` to forget to write.
- Cleanup follows the value when it moves. Returning a `File`, or putting
  it in a struct, moves the responsibility for closing it along with it. A
  Go `defer f.Close()` in the wrong function closes the file too early.
- In a loop, each iteration's value is dropped at the end of that
  iteration. In Go, `defer` in a loop piles up until the function returns.
:::

You can drop a value early by calling `drop(value)`. That's simply a
function that takes ownership and does nothing, so the value is dropped
when its parameter goes out of scope. You can't call `.drop()` directly.

There's one caveat: errors returned during cleanup are ignored, because
`drop` can't return anything. For files, call `file.sync_all()?`
explicitly if you need to know whether data reached disk. That's the same
advice as checking the error from `Close` in Go.

## Ownership is a tree

Owned values nest. A `Vec<String>` owns its buffer, and each `String` in it
owns its own buffer. A struct owns its fields. When you drop the root,
everything beneath it is dropped recursively. So a Rust program's data
forms a **tree of ownership**, with each node having exactly one parent.

Go's object graph can be any shape: cycles, multiple parents, back
pointers. The GC handles all of it. In Rust, any shape other than a tree
needs explicit tools: borrowing (temporary access without ownership,
Chapter 4), reference counting (`Rc`/`Arc`, Chapter 11) or indices into an
arena. That's why a doubly linked list is a classic Rust headache, and why
idiomatic Rust designs often look a little different from Go designs. Data
flows down the tree, and shared access is temporary.

## Moving out of things

You can move out of a local variable, but not out of something you only
have access to through a reference, and not out of the middle of a `Vec`.
Doing so would leave a hole:

```rust
let names = vec![String::from("a"), String::from("b")];
let first = names[0];          // error: cannot move out of index
let first = names[0].clone();  // ok: copy it
let first = &names[0];         // ok: borrow it (Chapter 4)
let first = names.into_iter().next(); // ok: consume the whole Vec
```

You can move fields out of an owned struct one at a time (a "partial
move"). After that, the struct as a whole can't be used, though its other
fields still can. When you want to take a value and leave something valid
behind, use `std::mem::take` (leaves `Default`), `std::mem::replace`, or
`Option::take` (leaves `None`). These come up frequently when working with
`&mut` references.

```rust
let mut buf = String::from("data");
let old = std::mem::take(&mut buf); // buf is now "", old is "data"
```

## Summary

- Assignment, argument passing and return **move** non-`Copy` values. The
  source is unusable afterwards.
- Moves are cheap shallow copies. `.clone()` is the explicit, potentially
  expensive deep copy.
- Values are freed when their owner goes out of scope (`Drop`). That
  replaces both the GC and `defer`.
- Data forms an ownership tree. Sharing requires borrowing or explicit
  shared-ownership types.

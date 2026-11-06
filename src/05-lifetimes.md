# Lifetimes

Every reference has a **lifetime**: the part of the program during which
it's valid. Until now the compiler has worked these out on its own. Some
signatures are ambiguous, though, and then you have to state the
relationship yourself. This is the most unusual-looking syntax in Rust,
but the idea behind it is simple.

## Why the compiler needs help

```rust
fn longest(a: &str, b: &str) -> &str {
    if a.len() >= b.len() { a } else { b }
}
// error[E0106]: missing lifetime specifier
// help: this function's return type contains a borrowed value, but
//       the signature does not say whether it is borrowed from `a`
//       or `b`
```

The compiler checks each function on its own, looking only at the
signatures of the functions it calls, never their bodies. A caller of
`longest` needs to know how long the returned reference stays valid, and
that depends on where it came from. Lifetime parameters say so:

```rust
fn longest<'a>(a: &'a str, b: &'a str) -> &'a str {
    if a.len() >= b.len() { a } else { b }
}
```

Read `'a` as "some region of code". The signature says that for some region
`'a` where both inputs are valid, the output is valid for that same region.
At each call site the compiler picks the largest `'a` that works, which is
the overlap of the two arguments' lifetimes, and checks that the result
isn't used beyond it:

```rust
let outer = String::from("long string");
let result;
{
    let inner = String::from("short");
    result = longest(&outer, &inner);
} // inner dropped here
println!("{result}");
// error[E0597]: `inner` does not live long enough
```

::: key
Lifetime annotations **never change** how long anything lives. They are
constraints that link the lifetimes of inputs and outputs, so the
compiler can check callers without looking inside the function. They're
similar to generic type parameters, except that they describe validity
instead of type.
:::

If the output depends on only one input, say so, and the other argument
is left unconstrained:

```rust
fn first_word<'a>(s: &'a str, _sep: &str) -> &'a str {
    s.split_whitespace().next().unwrap_or("")
}
```

## Elision: why you rarely write them

Most signatures need no annotations because of three **elision rules**:

1. Each reference parameter gets its own lifetime.
2. If there is exactly one input lifetime, it is assigned to all output
   references.
3. If there is a `&self` or `&mut self` parameter, its lifetime is assigned
   to all output references.

So `fn trim(s: &str) -> &str` is shorthand for
`fn trim<'a>(s: &'a str) -> &'a str`, and a method like
`fn name(&self) -> &str` returns something borrowed from `self`. You only
write lifetimes when the rules can't decide, which typically means several
reference inputs and a reference output, or a struct that holds a
reference.

## Structs that hold references

A struct can borrow data instead of owning it, but it then has to carry a
lifetime parameter. That way the compiler can make sure the struct doesn't
outlive the data it borrows:

```rust
struct Parser<'src> {
    input: &'src str,
    pos: usize,
}

impl<'src> Parser<'src> {
    fn new(input: &'src str) -> Self {
        Parser { input, pos: 0 }
    }

    /// Returned tokens borrow from the *input*, not from the parser,
    /// so they stay valid after the parser is dropped.
    fn next_token(&mut self) -> Option<&'src str> {
        let rest = &self.input[self.pos..];
        let rest_trim = rest.trim_start();
        let start = self.pos + (rest.len() - rest_trim.len());
        let len = rest_trim.find(' ').unwrap_or(rest_trim.len());
        if len == 0 { return None; }
        self.pos = start + len;
        Some(&self.input[start..start + len])
    }
}
```

The return type is the interesting part. Under elision rule 3, the
signature would have been `fn next_token(&mut self) -> Option<&str>`, tied
to the borrow of `self`. Callers then couldn't keep a token while calling
`next_token` again. Writing `'src` explicitly says that the token borrows
from the source text, not from the parser. Choosing between these is the
main design decision you make with lifetimes.

This is how Rust does **zero-copy parsing**. Tokens are slices of the
original buffer and are checked so that they can't outlive it. Go does
the same with `[]byte` subslices, but nothing stops you from holding a
subslice after the buffer has been reused, for example with a
`bufio.Scanner`, whose `Bytes()` documentation warns that the slice may be
overwritten by the next call.

::: warn
Don't reach for struct lifetimes by default. A struct holding a reference
can't outlive whatever it borrows from, and every struct that contains it
inherits the lifetime parameter. For application-level types such as
config, request handlers or domain objects, **own your data** (`String`,
`Vec<T>`) unless profiling says otherwise. Borrowing structs suit
short-lived views: parsers, iterators, guards and formatters.
:::

## `'static`

`'static` is the lifetime of the entire program. String literals are
`&'static str` because they live in the binary's read-only data.

You'll mostly see `'static` as a **bound**, `T: 'static`, and this is often
misread. It does **not** mean that the value lives forever. It means that
the type **contains no borrowed references with a shorter lifetime**. Every
owned type, such as `String`, `Vec<u8>` or `Arc<Config>`, satisfies
`'static`.

```rust
pub fn spawn<F, T>(f: F) -> JoinHandle<T>
where
    F: FnOnce() -> T + Send + 'static,
    T: Send + 'static,
```

This is `std::thread::spawn`. The closure must be `'static` because the new
thread may outlive the caller's stack frame, so it can't borrow local
variables. In Go, a goroutine can capture anything because the GC keeps it
alive. In Rust you move owned data in, share it through `Arc` (Chapter 11),
or use scoped threads (Chapter 13).

## Lifetimes in practice

A few more forms you'll see:

```rust
impl<'a> Parser<'a> { }        // impl for a lifetime-generic type
fn show(p: &Parser<'_>) { }     // '_ : "some lifetime, inferred"
struct Ctx<'a, T: 'a> { x: &'a T } // T must outlive 'a (usually implied)
fn f<'a, 'b: 'a>(x: &'a str, y: &'b str) { } // 'b outlives 'a
```

When you see an error about lifetimes, it almost always falls into one of
these categories:

- **"does not live long enough"**: a reference is used after its owner is
  dropped. Move the owner to an outer scope, or return an owned value.
- **"lifetime may not live long enough"** or **"explicit lifetime
  required"**: a signature doesn't say where a returned reference comes
  from. Add a lifetime parameter that links output to input.
- **"borrowed value must be valid for the static lifetime"** or
  **"may outlive borrowed value"**: you passed a borrow to a thread or
  task. Move owned data in instead (`move` closures, `Arc`, `clone`).

## Summary

- A lifetime is the region in which a reference is valid. Annotations link
  regions together; they never extend them.
- The elision rules cover most functions. Annotate when a function returns
  a reference and has several reference inputs.
- Structs with references need lifetime parameters. Prefer owned fields
  unless you're writing a short-lived view.
- `T: 'static` means "no short-lived borrows inside", which is what threads
  and async tasks require.

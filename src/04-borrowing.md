# Borrowing

If moving were the only way to pass values around, every function would
have to take ownership and hand it back. **Borrowing** lets you give code
temporary access to a value without transferring ownership.

## References

```rust
fn total_len(words: &Vec<String>) -> usize {
    let mut n = 0;
    for w in words {
        n += w.len();
    }
    n
}

let words = vec!["a".to_string(), "bc".to_string()];
let n = total_len(&words); // lend `words`
println!("{n} {words:?}"); // still ours
```

`&T` is a **shared reference** and `&mut T` is a **mutable (exclusive)
reference**. At machine level both are just pointers, like Go's `*T`. They
differ from Go pointers in three ways:

- **They never own.** Dropping a reference does nothing. The owner frees
  the value.
- **They're never null.** "Maybe there's a value" is written `Option<&T>`
  (Chapter 6).
- **They can never dangle.** The compiler proves that the referent outlives
  every reference to it. You can't return a reference to a local, keep a
  reference into a `Vec` that has since reallocated, or use a reference
  after the owner has been dropped.

```rust
fn dangle() -> &String {   // error: missing lifetime specifier
    let s = String::from("hi");
    &s                      // s is dropped at the end of this fn
}
```

In Go this would be fine, because escape analysis would move `s` to the
heap. In Rust you return the owned `String` instead.

## The borrowing rule

At any point in the program, a value can have **either**:

- any number of shared references `&T`, **or**
- exactly one mutable reference `&mut T`,

but never both. While a value is borrowed, its owner is also restricted.
It can't move the value away, and if the borrow is shared, it can't mutate
it.

::: key
**Aliasing XOR mutability.** Data can be shared or mutated, but not both at
the same time. Nearly every borrow checker error comes back to this rule.
:::

The following Go bug is exactly what the rule prevents:

```go
users := []User{{Name: "ann"}}
first := &users[0]
users = append(users, User{Name: "bob"}) // may reallocate
first.Name = "ANN" // writes to the OLD array; users[0] unchanged
```

Go doesn't crash here, because the GC keeps the old array alive, but the
program silently does the wrong thing. In Rust:

```rust
let mut users = vec![User { name: "ann".into() }];
let first = &mut users[0];
users.push(User { name: "bob".into() });
// error[E0499]: cannot borrow `users` as mutable more than once
first.name = "ANN".into();
```

`first` is a live mutable borrow of `users`, and `push` needs another one.
The same rule rules out iterator invalidation, modifying a map while
ranging over it, and, as Chapter 13 shows, data races between threads.

## Borrows end at last use

The borrow checker reasons about where each reference is *used*, not about
lexical scope. A borrow lasts from its creation to its last use. (The
feature is called *non-lexical lifetimes*.)

```rust
let mut v = vec![1, 2, 3];
let first = &v[0];
println!("{first}"); // last use of `first`
v.push(4);           // fine: the shared borrow has ended
```

Swapping the last two lines gives an error, because `first` would still be
alive when `push` needs exclusive access.

## Using references

You create references with `&` and `&mut`, and dereference them with `*`.
Most of the time dereferencing is automatic. The method-call operator `.`
dereferences as many times as needed, much as Go lets you call methods
through a pointer:

```rust
let mut n = 10;
let r = &mut n;
*r += 1;               // explicit deref for assignment

let s = String::from("hi");
let rs = &s;
let rrs = &rs;
println!("{}", rrs.len()); // auto-deref through && to String
```

Comparison operators work through references (`&a == &b` compares the
values). Arithmetic on `&i32` works for the common cases.

## Methods and `self`

Methods live in `impl` blocks, and the receiver says how the method uses
the value:

```rust
struct Counter { hits: u64 }

impl Counter {
    fn new() -> Self { Counter { hits: 0 } } // no receiver: a constructor
    fn get(&self) -> u64 { self.hits }        // shared borrow
    fn hit(&mut self) { self.hits += 1; }     // exclusive borrow
    fn finish(self) -> u64 { self.hits }      // takes ownership
}

let mut c = Counter::new();
c.hit();             // auto-borrows &mut c
let n = c.finish();  // c moved; can't be used after this
```

| Go receiver          | Rust receiver | Meaning                           |
|----------------------|---------------|-----------------------------------|
| `func (c Counter)`   | `self`        | Go copies; Rust takes ownership  |
| `func (c *Counter)`  | `&self`       | read-only access                  |
| `func (c *Counter)`  | `&mut self`   | read–write access                 |

Go uses pointer receivers for two different reasons, to avoid copying and
to allow mutation, and the signature doesn't say which. Rust's signature
does. A `self` receiver is a *consuming* method: `finish` above,
`into_iter()`, `String::into_bytes()`, or a builder's `build()`. These can
express "after this call, the object is gone", which Go can't express.

## Choosing parameter types

A practical rule for function signatures:

- Take `&T` when you only need to read. This is the most common case.
- Take `&mut T` when you need to modify the caller's value in place.
- Take `T` by value when you need to *keep* it, for example to store it in
  a struct or send it to another thread, or when it's small and `Copy`.

Accept the most general borrowed form. Use `&str` rather than `&String`,
and `&[T]` rather than `&Vec<T>`. Both of these coerce automatically
(Chapter 9):

```rust
fn shout(s: &str) -> String { s.to_uppercase() }
fn sum(xs: &[i64]) -> i64 { xs.iter().sum() }

let owned = String::from("hey");
shout(&owned);   // &String coerces to &str
shout("literal");
sum(&vec![1, 2]);
sum(&[1, 2, 3]);
```

## Fighting the borrow checker

The borrow checker is conservative. Sometimes it rejects programs that
are actually safe. Learning Rust largely means learning a few standard ways
to restructure code. These are the situations you'll run into in your first
weeks.

### 1. Mutating a collection while iterating

```rust
for item in &items {
    if item.expired() {
        items.retain(|i| !i.expired()); // error: items already borrowed
    }
}
```

Look for a method that does the job in one go (`retain`, `drain`,
`dedup_by`, `sort_by_key`). Otherwise, collect what you need first and
mutate afterwards, or iterate over indices:

```rust
items.retain(|i| !i.expired());

for i in 0..items.len() {
    if items[i].needs_bump() { items[i].bump(); }
}
```

### 2. Borrowing two fields through methods

```rust
impl Game {
    fn player_mut(&mut self) -> &mut Player { &mut self.player }

    fn tick(&mut self) {
        let p = self.player_mut();  // borrows ALL of self mutably
        p.update(&self.world);      // error: self already borrowed
    }
}
```

The compiler tracks borrows of individual fields within a function body,
but a method call borrows the whole receiver. Access the fields directly so
that the borrows are visibly disjoint:

```rust
fn tick(&mut self) {
    let p = &mut self.player;
    p.update(&self.world); // fine: different fields
}
```

For two disjoint elements of a slice, use `split_at_mut`, or
`get_disjoint_mut` on slices and `HashMap`s.

### 3. Look up, then insert

```rust
fn get_or_compute(map: &mut HashMap<String, u64>, key: String)
    -> &u64
{
    if let Some(v) = map.get(&key) {
        return v; // returning the borrow keeps `map` borrowed...
    }
    map.insert(key.clone(), compute()); // ...so this is an error
    &map[&key]
}
```

This is a known limitation of the current borrow checker: the code is safe,
and a future checker (Polonius) will accept it. Today you use the **entry
API**, which also does a single hash lookup instead of two or three:

```rust
fn get_or_compute(map: &mut HashMap<String, u64>, key: String)
    -> &u64
{
    map.entry(key).or_insert_with(compute)
}
```

### 4. Storing a reference in a long-lived struct

Usually you want the struct to own the data instead. See the next chapter.

::: go
You might expect the borrow checker to feel like a stricter `go vet`. In
practice it pushes your design towards data with a single clear owner,
mutation in few places, and short-lived shared access. These are good
habits in Go too, especially in concurrent code. Most experienced Rust
programmers say that after a few months they rarely fight the borrow
checker, because they've stopped writing the shapes it rejects.
:::

## Slices are borrows

A slice `&[T]` is a borrowed view into contiguous memory (pointer +
length), just like Go's slice header but without the capacity and without
the ability to grow. `&mut [T]` lets you modify elements, but not change the
length.

```rust
let mut v = vec![5, 3, 8, 1];
let middle = &v[1..3];        // [3, 8]
let tail = &mut v[2..];
tail.sort();                  // sorts only the tail
```

Because a slice borrows from its owner, the owner can't reallocate while
the slice exists. Go's `append` aliasing bugs, where two slices share an
array and an `append` through one overwrites data visible to the other,
can't happen in Rust.

## Summary

- `&T` shares, `&mut T` grants exclusive access. Neither owns, and neither
  can dangle or be null.
- Shared XOR mutable. Borrows end at their last use.
- Receivers state their intent: `&self`, `&mut self`, or `self` (consume).
- When the checker refuses, restructure: use collection methods, access
  fields directly, use the entry API, or have structs own their data.

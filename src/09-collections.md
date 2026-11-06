# Strings and Collections

## `String` and `&str`

Go has one string type: an immutable, cheaply copyable byte sequence that
is UTF-8 by convention. Rust has two main ones, which follow the
owned/borrowed split from Chapter 4:

| Type        | Owns data? | Mutable? | Analogy                         |
|-------------|------------|----------|---------------------------------|
| `String`    | yes (heap) | yes      | `strings.Builder` you can also read |
| `&str`      | no         | no       | Go `string` (a borrowed view)   |

```rust
let lit: &str = "hello";            // &'static str, in the binary
let mut s: String = String::from("hello");
s.push_str(", world");
s.push('!');
let view: &str = &s;                // borrow the whole String
let part: &str = &s[0..5];          // byte-range slice: "hello"
let owned: String = part.to_string(); // or .to_owned(), String::from
```

Rust strings are **guaranteed valid UTF-8**. That's a type invariant, not a
convention. Raw bytes are `Vec<u8>` / `&[u8]`, and converting from bytes is
checked: `String::from_utf8(bytes)` returns a `Result`. (Go will happily
put invalid UTF-8 into a `string`.)

Paths and OS strings have their own types: `PathBuf`/`&Path` and
`OsString`/`&OsStr`. Unix file names don't have to be valid UTF-8, so they
don't fit in `String`.

### Indexing

```rust
let s = "naïve";
let c = s[2];        // error: strings cannot be indexed by integer
let b = s.as_bytes()[2];  // 0xC3, a raw byte
let sub = &s[0..2];       // "na": byte ranges are allowed...
let bad = &s[0..3];       // ...but this PANICS: not a char boundary
```

Go lets you index a string by byte (`s[2]`) and returns a byte. Rust
refuses, because it's ambiguous whether you mean a byte or a character.
You say which you mean:

```rust
for ch in s.chars() { }          // like Go's `for _, r := range s`
for (i, ch) in s.char_indices() { } // byte offset + char
for b in s.bytes() { }           // like `for i := 0; i < len(s); i++`
let n_chars = s.chars().count(); // O(n), like utf8.RuneCountInString
let len_bytes = s.len();         // O(1), bytes, like len(s)
```

### Common operations

| Go                               | Rust                                   |
|----------------------------------|----------------------------------------|
| `a + b`                          | `a + &b` (consumes `a`) or `format!("{a}{b}")` |
| `strings.Contains(s, x)`         | `s.contains(x)`                        |
| `strings.HasPrefix(s, p)`        | `s.starts_with(p)`                     |
| `strings.TrimPrefix(s, p)`       | `s.strip_prefix(p)` → `Option<&str>`   |
| `strings.Split(s, ",")`          | `s.split(',')` → iterator              |
| `strings.Fields(s)`              | `s.split_whitespace()`                 |
| `strings.Cut(s, "=")`            | `s.split_once('=')` → `Option<(&str, &str)>` |
| `strings.Join(xs, ", ")`         | `xs.join(", ")`                        |
| `strings.ToUpper(s)`             | `s.to_uppercase()`                     |
| `strings.TrimSpace(s)`           | `s.trim()`                             |
| `strings.Replace(s, a, b, -1)`   | `s.replace(a, b)`                      |
| `strconv.Itoa(n)`                | `n.to_string()`                        |
| `strconv.Atoi(s)`                | `s.parse::<i64>()`                     |
| `strings.Builder`                | `String` + `push_str` / `write!`       |

Most of these return borrowed `&str` slices into the original instead of
allocating, so they're cheap, and the borrow checker makes sure the
original stays alive.

### Which type to use

- Function parameters: `&str`.
- Struct fields and return values that create new text: `String`.
- Something that may or may not need to allocate: `Cow<'_, str>`
  (Chapter 11).
- To accept either: `impl Into<String>` (if you'll store it) or
  `impl AsRef<str>`.

## `Vec<T>`

`Vec<T>` is Go's slice in its role as a growable array: a pointer, length
and capacity, owning a heap buffer.

```rust
let mut v: Vec<i32> = Vec::new();
let mut w = Vec::with_capacity(100);  // make([]T, 0, 100)
let z = vec![0; 10];                  // make([]T, 10)
v.push(1);                            // append(v, 1)
v.extend([2, 3, 4]);                  // append(v, xs...)
v.extend_from_slice(&other);
let last = v.pop();                   // Option<i32>
v.insert(0, 9);  v.remove(0);         // O(n), like slices.Insert/Delete
v.truncate(2);   v.clear();
v.sort();  v.sort_by_key(|x| -x);  v.dedup();
v.contains(&3);  v.binary_search(&3);
v.iter().position(|&x| x == 3);       // slices.Index
let s: &[i32] = &v[1..];              // borrow a slice
```

Indexing out of bounds panics, just as in Go. `v.get(i)` returns an
`Option<&T>` instead. Since a `Vec` owns its elements, removing one gives
you ownership of it (`pop`, `remove`, `swap_remove`, `drain`).

The big difference from Go: **a `Vec` and the slices borrowed from it can't
alias in surprising ways.** In Go, `b := a[:2]; b = append(b, x)` can
overwrite `a[2]`. The Rust equivalent doesn't compile, because `b` would be
a borrow of `a`, and `push` needs ownership or `&mut` of the `Vec` itself.

Other sequence types:

- `[T; N]`: a fixed-size array on the stack.
- `VecDeque<T>`: a ring buffer (queue, deque).
- `BinaryHeap<T>`: a priority queue (cf. `container/heap`, but generic).
- `Box<[T]>`: a fixed-length heap slice, smaller than a `Vec`.
- `smallvec` / `arrayvec` crates: small inline buffers that avoid heap
  allocation.

## `HashMap<K, V>`

```rust
use std::collections::HashMap;

let mut ages: HashMap<String, u32> = HashMap::new();
ages.insert("ann".to_string(), 31);   // returns Option<old value>
if let Some(a) = ages.get("ann") { }  // m["ann"] with ok-check
let a = ages.get("bob").copied().unwrap_or(0); // zero-value default
ages.remove("ann");                   // delete(m, k), returns Option<V>
ages.contains_key("ann");
for (name, age) in &ages { }          // iteration order unspecified
```

There are a few differences from Go maps:

- **No zero value on missing keys.** `get` returns an `Option`, and
  `ages["bob"]` panics if the key is absent.
- **No nil map trap.** `HashMap::new()` doesn't allocate until the first
  insert, and there's no nil state that panics on write.
- **Keys must be `Eq + Hash`.** Derive both for your own key types.
- **Lookups take borrowed forms.** A `HashMap<String, _>` can be queried
  with a `&str`, thanks to the `Borrow` trait, so you don't need to
  allocate a `String` just to look something up.
- **The hasher resists HashDoS** (SipHash-1-3). It's slower than Go's
  AES-based hash for small keys. Crates such as `ahash`, `foldhash` or
  `rustc-hash` (`FxHashMap`) are faster when keys aren't attacker-controlled.

### The entry API

This is the idiomatic way to do "insert or update":

```rust
// Word count. Go: counts[w]++
let mut counts: HashMap<&str, usize> = HashMap::new();
for w in text.split_whitespace() {
    *counts.entry(w).or_insert(0) += 1;
}

// Group by. Go: groups[k] = append(groups[k], v)
let mut groups: HashMap<char, Vec<&str>> = HashMap::new();
for w in words {
    let k = w.chars().next().unwrap();
    groups.entry(k).or_default().push(w);
}
```

`entry` hashes once and gives you a handle you can inspect
(`Entry::Occupied` / `Entry::Vacant`) or fill in. Go needs two lookups for
this, and sometimes a `nil` check on the inner slice.

### Other maps and sets

- `BTreeMap<K, V>` / `BTreeSet<T>`: sorted by key and iterated in order,
  with range queries (`map.range(a..b)`). Go has nothing like this in the
  standard library.
- `HashSet<T>`: Go's `map[T]struct{}`, done properly, with `union`,
  `intersection` and `difference`.
- `indexmap` crate: a hash map that preserves insertion order.

## Ownership and collections

Moving a value into a collection transfers ownership. Iterating comes in
three flavours, according to what you want to do with the elements:

```rust
for x in &v { }       // x: &T      — read (v.iter())
for x in &mut v { }   // x: &mut T  — modify in place (v.iter_mut())
for x in v { }        // x: T       — consume v (v.into_iter())
```

Go's `for _, x := range v` copies each element into `x`, so writing to `x`
has no effect, which is a classic bug. In Rust, `for x in &mut v { *x += 1 }`
modifies the elements in place, and `for x in v` makes it explicit that
`v` is consumed.

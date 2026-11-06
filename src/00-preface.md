# Preface {.unnumbered}

You already know how to program. You know what a hash map is, why you should
check errors, how a mutex works, and what goes wrong when two goroutines write
to the same map. This book does not re-teach any of that. It's about the parts
of Rust that are actually new to a Go programmer, and about mapping the parts
that aren't new onto what you already know.

Go and Rust are closer than they look. Both came out of frustration with [C++]{.nobr}.
Both compile to native code, ship static binaries, prefer composition to
inheritance, return errors as values, have a canonical formatter and a
built-in test runner. They also make opposite bets in one important area:

- **Go** puts simplicity first. A garbage collector manages memory, the
  runtime schedules goroutines, and the type system stays small on purpose.
  You give up some control and some compile-time guarantees, and in return a
  new team member can read the code after a week.
- **Rust** puts correctness and control first. There is no garbage collector
  and no hidden runtime. Ownership of memory is tracked by the compiler, and
  the type system is expressive enough to rule out entire classes of bugs:
  use-after-free, data races, null de&shy;refer&shy;ences, forgotten error checks.
  The cost is a steeper learning curve and a compiler that argues with you.

Most of your effort will go into that argument with the compiler. The goal of
this book is to get you through it quickly, by explaining the *model* the
compiler is enforcing, so that its error messages turn into hints rather than
obstacles.

## How this book is organized {-}

Chapters 1–2 cover tooling and basic syntax, quickly. Chapters 3–5 cover
ownership, borrowing and lifetimes. This is the core of the language and the
part with no equivalent in Go, so it gets the most space. Read these chapters
slowly and in order.

Chapters 6–11 cover the type system: enums and pattern matching, error
handling, traits and generics, collections, closures and iterators, and
smart pointers. Chapter 12 covers modules, Cargo and testing. Chapters 13–14
cover concurrency, first with threads and then with `async`, which is the
place where Go's design and Rust's design differ most visibly. The last
chapters cover macros, `unsafe`, and how to translate familiar Go idioms.
The appendices are a quick-reference phrasebook and a map from Go's
standard library to the Rust crates you'll use instead.

## Conventions {-}

Code blocks are labeled **Go** or **Rust** in the corner, so you can tell
them apart at a glance. Boxes titled *Coming from Go* point out where your
Go intuition will help or mislead you. Boxes titled *Watch out* flag common
traps.

Examples target Rust 2024 edition (stable since Rust 1.85) and Go 1.23+.
Snippets are often fragments; where a complete program matters, it is shown
in full. Type everything into a scratch project and compile it. Reading the
compiler's errors is part of learning Rust.

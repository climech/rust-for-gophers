# Rust for Gophers

A concise book that teaches Rust to developers who already know Go. It
compares Rust with Go wherever it can and spells out where the two languages
differ.

The book moves quickly through material an experienced programmer already
knows, such as syntax, tooling and collections. It spends most of its pages
on the ideas Go has no equivalent for:

- ownership, borrowing and lifetimes
- traits and generics
- `async`

It is about 116 pages.

**Read it:** [`rust-for-gophers.pdf`](rust-for-gophers.pdf)

## Contents

Preface

1. Getting Started
2. The Basics, Quickly
3. Ownership
4. Borrowing
5. Lifetimes
6. Structs, Enums and Pattern Matching
7. Error Handling
8. Traits and Generics
9. Strings and Collections
10. Closures and Iterators
11. Smart Pointers and Interior Mutability
12. Modules, Crates and Testing
13. Concurrency with Threads
14. Async Rust
15. A Tour of the Ecosystem
16. Macros
17. Unsafe Rust and FFI
18. Translating Go Idioms

Appendices:

- A: Phrasebook (Go construct → Rust equivalent)
- B: Standard Library Map (Go package → Rust crate)

The examples target Rust 2024 edition and Go 1.23+.

## Building from source

The book is written in Markdown (`src/`). [pandoc](https://pandoc.org)
converts it to HTML, and [WeasyPrint](https://weasyprint.org) typesets that
HTML as the PDF.

Requirements:

- pandoc 3.x
- Python 3 with WeasyPrint
- `pdfinfo` from poppler-utils (optional; the build uses it to report the
  page count)

```sh
python3 -m venv .venv && .venv/bin/pip install weasyprint
WEASYPRINT=.venv/bin/weasyprint ./build.sh
```

If `weasyprint` is already on your `PATH`, just run `./build.sh`.

The build writes intermediate HTML to `build/` and the final PDF to
`rust-for-gophers.pdf`.

## Project layout

| Path            | What it is                                        |
|-----------------|---------------------------------------------------|
| `src/*.md`      | Chapters, assembled in filename order             |
| `src/meta.yaml` | Title, subtitle, author, date                     |
| `template.html` | pandoc HTML template (title page, contents, body) |
| `style.css`     | Page layout and typography (print CSS)            |
| `fonts/`        | Source Serif 4, Inter, Iosevka                    |
| `build.sh`      | Build script                                      |

## Credits

Written by Claude Opus 5.5.

Typefaces:

- [Source Serif 4](https://github.com/adobe-fonts/source-serif) and
  [Inter](https://rsms.me/inter/) are under the SIL Open Font License.
- [Iosevka](https://github.com/be5invis/Iosevka) is also under the SIL Open
  Font License.

## License

The book's text, code examples and build files are released under the
[MIT License](LICENSE).

The fonts in `fonts/` are not covered by it. They keep their own licence, the
SIL Open Font License 1.1. The licence text and copyright notice for each
font are in `fonts/OFL-*.txt`.

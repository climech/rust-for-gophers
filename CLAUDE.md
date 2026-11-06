# Rust for Gophers

A short book (~116 pages, A5 PDF) that teaches Rust to experienced Go
developers, drawing parallels to Go and highlighting differences. Concise on
familiar concepts, deeper on foreign ones (ownership, borrowing, lifetimes,
traits, async). Keep the total under ~150 pages.

The output is `rust-for-gophers.pdf` at the repo root. Author on the title page: the
AI model name (`src/meta.yaml`).

## Build

```sh
./build.sh                                  # needs pandoc + weasyprint on PATH
WEASYPRINT=/path/to/venv/bin/weasyprint ./build.sh
```

Pipeline: pandoc (Markdown → `build/book.html` via `template.html`, with TOC,
section numbers and pygments highlighting) → WeasyPrint (HTML + `style.css` →
PDF). WeasyPrint isn't installed system-wide. Install it in a venv
(`pip install weasyprint`) if no venv exists. `build/` is generated output.

To check the result visually, render pages with
`pdftoppm -png -r 60 -f N -l M rust-for-gophers.pdf out` and look at them.

## Layout

- `src/NN-*.md`: chapters, concatenated in filename order.
  - `00-preface` and the appendices (`19-`, `20-`) are `{.unnumbered}`.
  - Appendix subsections use `{-}`.
- `src/meta.yaml`: title, subtitle, author, date.
- `template.html`: pandoc template (title page, TOC, body).
- `style.css`: all typography and paged-media rules (A5, running headers, page
  numbers, TOC leaders, chapter openers, callouts, code labels).
- `fonts/`: Source Serif 4 (body), Inter (headings), Iosevka (code). Fonts are
  loaded from local files only, via `fonts/fonts-local.css`.

## Writing conventions

- **Callout boxes** are pandoc fenced divs:
  - `::: go` renders as "Coming from Go".
  - `::: note` is a note.
  - `::: warn` renders as "Watch out".
  - `::: key` renders as "Key idea".
- Use the `rust`, `go`, `toml`, `sh` or `text` info string on code blocks. The
  language is shown as a corner label.
- **Ligatures:** they are disabled in code. Keep it that way, because `=>` and
  `!=` must render literally.
- **Words that must not break:** wrap them in `[C++]{.nobr}`. Body text is
  justified and hyphenated.
- **Pipe characters in tables:** inside inline code in pipe tables, `\|` shows
  a literal backslash. Use raw HTML instead, for example
  `<code>a &#124; b</code>` (and `&amp;` for `&`).
- **Spelling:** American English (`behavior`, `initialize`, `canceled`).
- **Prose style:** plain and direct. Short sentences, no filler, no
  over-explaining basics to an experienced programmer.

## Accuracy

Examples target Rust 2024 edition (Rust 1.85+) and Go 1.23+. Verify claims
about compiler behavior by compiling a snippet with `rustc`. That includes
which code fails, the exact error codes, and when features became stable. Many
book snippets are deliberate fragments or deliberate compile errors, so don't
"fix" those.

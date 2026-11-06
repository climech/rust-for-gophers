#!/usr/bin/env bash
# Build the book: Markdown -> HTML (pandoc) -> PDF (WeasyPrint).
set -euo pipefail
cd "$(dirname "$0")"
WEASY="${WEASYPRINT:-weasyprint}"
pandoc src/[0-9]*.md \
  --from markdown+fenced_divs+pipe_tables+smart \
  --to html5 --standalone --template template.html \
  --metadata-file src/meta.yaml \
  --toc --toc-depth=2 --number-sections \
  --syntax-highlighting=pygments 2>/dev/null \
  -o build/book.html || \
pandoc src/[0-9]*.md \
  --from markdown+fenced_divs+pipe_tables+smart \
  --to html5 --standalone --template template.html \
  --metadata-file src/meta.yaml \
  --toc --toc-depth=2 --number-sections \
  --highlight-style=pygments \
  -o build/book.html
cp style.css build/ && rm -rf build/fonts && cp -r fonts build/
"$WEASY" build/book.html rust-for-gophers.pdf
pdfinfo rust-for-gophers.pdf | grep -E "Pages|Page size"

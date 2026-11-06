# Appendix B: Standard Library Map {.unnumbered}

Where to find the equivalent of each Go standard-library package. "std"
means it's in Rust's standard library. Everything else is a crate on
crates.io. Where several crates are listed, the first is the most common
choice.

| Go package               | Rust                                           |
|--------------------------|------------------------------------------------|
| `fmt`                    | std: `format!`, `println!`, `std::fmt`         |
| `strings`, `bytes`       | std: methods on `str`, `[u8]`; `bstr`          |
| `strconv`                | std: `parse()`, `to_string()`                  |
| `unicode/utf8`           | std: `char`, `str::chars`; `unicode-segmentation` |
| `errors`                 | std: `std::error::Error`; `thiserror`, `anyhow` |
| `sort`, `slices`, `maps` | std: slice and iterator methods; `itertools`   |
| `container/heap`, `list` | std: `BinaryHeap`, `VecDeque`, `LinkedList`    |
| `io`, `bufio`            | std: `std::io` (`Read`, `Write`, `BufReader`)  |
| `os`, `os/exec`          | std: `std::fs`, `std::env`, `std::process`     |
| `path/filepath`          | std: `std::path` (`Path`, `PathBuf`)           |
| `io/fs` walking          | `walkdir`, `ignore`                            |
| `os/signal`              | `tokio::signal`, `signal-hook`, `ctrlc`        |
| `flag`                   | `clap`, `argh`, `lexopt`                       |
| `log`, `log/slog`        | `tracing` + `tracing-subscriber`; `log`        |
| `time`                   | std: `Duration`, `Instant`, `SystemTime`; `jiff`, `chrono`, `time` |
| `sync`, `sync/atomic`    | std: `std::sync`; `parking_lot`, `crossbeam`   |
| `context`                | future dropping; `tokio_util::CancellationToken` |
| `net`                    | std: `std::net`; `tokio::net`                  |
| `net/http` (server)      | `axum`, `actix-web`, `hyper`                   |
| `net/http` (client)      | `reqwest`, `ureq` (blocking)                   |
| `net/http/httptest`      | `axum-test`, `wiremock`, `tower::ServiceExt::oneshot` |
| `net/url`                | `url`                                          |
| `encoding/json`          | `serde` + `serde_json`                         |
| `encoding/xml`           | `quick-xml`                                    |
| `encoding/csv`           | `csv`                                          |
| `encoding/base64`, `hex` | `base64`, `hex`                                |
| `encoding/binary`        | std: `u32::from_le_bytes` etc.; `byteorder`, `zerocopy` |
| gob / protobuf / gRPC    | `bincode`, `prost`, `tonic`                    |
| `text/template`, `html/template` | `askama`, `minijinja`, `tera`          |
| `regexp`                 | `regex`                                        |
| `crypto/*`               | `rustls`, `ring`, `aws-lc-rs`, RustCrypto crates (`sha2`, [`aes-gcm`]{.nobr}, …) |
| `crypto/rand`, `math/rand` | `rand`, `getrandom`                          |
| `math/big`               | `num-bigint`, `rug`                            |
| `database/sql`           | `sqlx`, `diesel`, `tokio-postgres`, `rusqlite` |
| `embed`                  | std: `include_str!`, `include_bytes!`; `rust-embed` |
| `testing`                | std: `#[test]`; `rstest`, `proptest`, `insta`  |
| `testing` benchmarks     | `criterion`, `divan`                           |
| `runtime/pprof`          | `pprof` crate, `perf`, `samply`                |
| `reflect`                | none; derive macros (`serde`, `strum`) instead |
| `unsafe`                 | std: `unsafe` blocks, `std::ptr`, `std::mem`   |
| `plugin`                 | `libloading`, or WebAssembly (`wasmtime`)      |
| `compress/gzip`, `zlib`  | `flate2`                                       |
| `archive/tar`, `zip`     | `tar`, `zip`                                   |
| `hash/crc32`, `fnv`      | `crc32fast`, `fnv`, `xxhash-rust`              |
| `html` parsing           | `scraper`, `html5ever`                         |
| `image`                  | `image`                                        |
| `os/user`                | `uzers`, `whoami`                              |
| `syscall`, `x/sys`       | `libc`, `nix`, `rustix`, `windows`             |

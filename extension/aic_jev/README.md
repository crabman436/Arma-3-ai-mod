# aic_jev — the AI Commander Jev extension

`aic_jev` is a tiny native extension (Rust, [arma-rs](https://github.com/BrettMayson/arma-rs))
that lets the AI Commander mod ask the **Jev** decision model
([TypeSafe AI](https://docs.typesafe.ai)) for judgment calls. Arma cannot do
HTTP from SQF, so the extension posts the request to
`https://api.typesafe.ai/v1/systemone` on a background thread and hands the
answer back through the engine's `ExtensionCallback` mission event handler.
The game thread never waits on the network.

Everything in the mod keeps working without this extension: if the binary,
the key or the network is missing, the commander falls back to its scripted
heuristics (see `CONTRACT.md`, section "Jev extension").

## Commands

| SQF call | Returns | Effect |
|---|---|---|
| `"aic_jev" callExtension "version"` | `"1.0.0"` | presence test |
| `"aic_jev" callExtension ["status", []]` | `"ok"` / `"nokey"` | whether an API key was found |
| `"aic_jev" callExtension ["setKey", [key]]` | `"ok"` | sets the key at runtime (overrides env/file) |
| `"aic_jev" callExtension ["ask", [id, model, bodyJson]]` | `"queued"` / `"error:<msg>"` | posts `bodyJson` on a worker thread |

`ask` details:

- `id` is a number or a string; it is echoed back unchanged in the callback.
- `model` is only used when `bodyJson` has no `"model"` field.
- `bodyJson` is the complete request (`{"model","state","questions"}` as
  documented by TypeSafe). It must be a JSON object and at most 200 KB.
- Immediate errors: `error:toolarge`, `error:badjson`, `error:nokey`,
  `error:thread` (the OS refused to start a worker thread).
- Network: 10 s timeout for the whole request, one retry after 1 s on
  HTTP 429, any 5xx or a transport error. All other failures are reported
  through the callback.

## Callback format

The answer arrives as a mission event:

```sqf
addMissionEventHandler ["ExtensionCallback", {
    params ["_name", "_function", "_data"];
    if (_name != "aic_jev" || _function != "answer") exitWith {};
    (parseSimpleArray _data) params ["_id", "_ok", "_payload"];
    // ...
}];
```

`_data` is a string that `parseSimpleArray` reads as `[id, ok, payload]`:

- `ok` is `true` on success and `payload` is an array of
  `[qid, type, value, confidence, probsArray]`, one entry per question:
  - `noul`: `value` = probability (number), `confidence` = `abs(2*p-1)`,
    `probsArray` = `[["true", p], ["false", 1-p]]`
  - `choice`: `value` = chosen key (string), `confidence` from the API (`null` → 0),
    `probsArray` = `[[key, p], ...]`
  - `score`: `value` = score (number), `confidence` from the API (`null` → 0),
    `probsArray` = `[["0", p], ["1", p], ...]`
- `ok` is `false` on failure and `payload` is the error message string, e.g.
  `"HTTP 401: Invalid API key"`, `"HTTP 429: ..."`, `"transport: ..."` or
  `"malformed response: ..."`.

Strings are SQF-escaped (`"` doubled); numbers are plain (no exponent
notation, trailing zeros trimmed, at most 6 decimals).

Example: `[7,true,[["attack_now","noul",0.82,0.64,[["true",0.82],["false",0.18]]],["posture","choice","offensive",0.71,[["balanced",0.2],["defensive",0.09],["offensive",0.71]]]]]`

## Supplying the API key

Lookup order (first non-empty wins):

1. `"aic_jev" callExtension ["setKey", [key]]` from a **server-side** script
   (for example `initServer.sqf`), which overrides the other two.
2. The environment variable `TYPESAFE_API_KEY` of the server process.
3. A file named `aic_jev.key` (one line) in the Arma working directory, i.e.
   the directory the server/game was started from.

The key is never logged and never returned to SQF. `status` only reports
whether one was found.

## Where the binaries go

Arma loads an extension only from a mod folder that was passed with `-mod=` /
`-serverMod=`, and only from that mod folder's root. Put the binary next to
`mod.cpp`:

```
@AICommander/
├── mod.cpp
├── addons/
├── aic_jev_x64.dll      (Windows client and server)
└── aic_jev_x64.so       (Linux dedicated server)
```

On a Linux server the `.so` must be executable (`chmod +x aic_jev_x64.so`), and
the server must be allowed outbound HTTPS to `api.typesafe.ai`. Only the
server needs the extension; clients never call it.

Ready-made binaries live in `dist/` and are also produced by the
`build-extension` GitHub Actions workflow (artifacts `aic_jev-windows` and
`aic_jev-linux`).

## Building

Requires a stable Rust toolchain (`rustup`). No OpenSSL or other native
libraries: TLS is pure Rust (rustls + bundled roots).

```sh
cd extension/aic_jev
cargo test                 # unit tests (no network)
cargo build --release
# Linux:   target/release/libaic_jev.so            -> dist/aic_jev_x64.so
# Windows: target/release/aic_jev.dll              -> dist/aic_jev_x64.dll
```

Cross-compiling the Windows binary from Linux (MinGW; `.cargo/config.toml`
already names the linker):

```sh
sudo apt install mingw-w64
rustup target add x86_64-pc-windows-gnu
cargo build --release --target x86_64-pc-windows-gnu
cp target/x86_64-pc-windows-gnu/release/aic_jev.dll dist/aic_jev_x64.dll
```

The GitHub workflow builds the MSVC target on `windows-latest`; both the GNU
and MSVC builds export the same `RVExtension*` symbols.

Live round trip against the real API (ignored by default):

```sh
TYPESAFE_API_KEY=... cargo test --test live_api -- --ignored --nocapture
```

## Layout

- `src/lib.rs` — command table and the `ask` worker thread
- `src/sqf.rs` — SQF escaping/number formatting and the request id
- `src/key.rs` — key lookup order
- `src/jev.rs` — request completion and response → callback payload
- `src/http.rs` — HTTPS POST with timeout and retry
- `tests/live_api.rs` — ignored integration test

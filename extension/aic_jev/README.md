# aic_jev — the Jev general's radio

Server-side Arma 3 extension that sends the AI Commander's briefings to
TypeSafe's Jev decision model and hands the answers back to SQF. Only the
machine running the commander needs it (dedicated server, or the host in
singleplayer / hosted MP). See `docs/JEV_DESIGN.md` for the design and the
main README ("The Jev general") for how to use it.

## Build

Needs Rust (https://rustup.rs). From this folder:

```
cargo test                 # unit tests + an end-to-end test against a fake Jev server
cargo build --release
```

| Server | Built file | Rename to | Put it in |
|---|---|---|---|
| Windows 64-bit | `target/release/aic_jev.dll` | `aic_jev_x64.dll` | the mod folder root, next to `mod.cpp` (`@aic/`) |
| Linux 64-bit | `target/release/libaic_jev.so` | `aic_jev_x64.so` | the mod folder root (`@aic/`) |

Build the Windows DLL on Windows (the `x86_64-pc-windows-msvc` toolchain).

## API key

The key never passes through SQF or the mission. The extension reads, in
this order (later wins):

1. `aic_jev.cfg` in the server's working directory (the Arma server folder):

   ```
   api_key = ts-...
   # optional; per attempt, 1..9 s (the mod gives up on a briefing after 20 s)
   timeout_s = 8
   api_url = https://api.typesafe.ai/v1/systemone
   ```

2. Environment variables `TYPESAFE_API_KEY` and `AIC_JEV_URL`.

Comments go on their own line (`#`). Keep `aic_jev.cfg` out of version
control and mission files.

## Commands

| SQF | Returns |
|---|---|
| `"aic_jev" callExtension ["version", []]` | `["0.1.0", 0, 0]` |
| `"aic_jev" callExtension ["ready", []]` | `["ok", 0, 0]`, or `["no_key", 0, 0]` |
| `"aic_jev" callExtension ["ask", [id, model, stateJson, questionsJson]]` | `["queued", 0, 0]` or `["error:<reason>", 0, 0]` |

After `queued`, one `ExtensionCallback` arrives with name `"aic_jev"`:

- function `"answer"`, data `[id, [answer, ...], [latencyMs, inputTokens, model]]`
  - `[name, "noul", p]`
  - `[name, "choice", choice, confidence, [[option, p], ...]]` (the
    per-option list is dropped if the answer would be too long)
  - `[name, "score", score, confidence]`
- function `"error"`, data `[id, reason]`

Data is SQF array text for `parseSimpleArray`. The request runs on its own
thread (at most 4 at once), with one retry after 1 s on HTTP 429, 5xx or a
network error.

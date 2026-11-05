//! `aic_jev`: the AI Commander native extension that asks the Jev decision
//! model (TypeSafe AI, System One) over HTTPS on a worker thread and hands the
//! answer back to SQF through the `ExtensionCallback` mission event handler.
//!
//! Commands (`"aic_jev" callExtension [fn, args]`):
//! - `version` (no args)             → `"1.0.0"`
//! - `["status", []]`                → `"ok"` / `"nokey"`
//! - `["setKey", [key]]`             → `"ok"`
//! - `["ask", [id, model, bodyJson]]`→ `"queued"` / `"error:<msg>"`
//!
//! Callback: name `"aic_jev"`, function `"answer"`, data `[id, ok, payload]`
//! in SQF-array syntax (see `jev::callback_data`).

pub mod http;
pub mod jev;
pub mod key;
pub mod sqf;

use arma_rs::{Context, Extension, arma};

use sqf::RequestId;

/// Reported by `version`; kept equal to the crate version.
pub const EXTENSION_VERSION: &str = env!("CARGO_PKG_VERSION");
/// `_name` in the `ExtensionCallback` event handler.
pub const CALLBACK_NAME: &str = "aic_jev";
/// `_function` in the `ExtensionCallback` event handler.
pub const CALLBACK_FUNCTION: &str = "answer";
/// Largest request body `ask` accepts (the API limit is 64k tokens, far below this).
pub const MAX_BODY_BYTES: usize = 200 * 1024;

/// Replies to `ask` that are not `"queued"`.
pub const ERROR_NO_KEY: &str = "error:nokey";
pub const ERROR_TOO_LARGE: &str = "error:toolarge";
pub const ERROR_BAD_JSON: &str = "error:badjson";
pub const ERROR_THREAD: &str = "error:thread";
pub const REPLY_QUEUED: &str = "queued";

#[arma]
pub fn init() -> Extension {
    Extension::build()
        .version(EXTENSION_VERSION.to_string())
        .allow_no_args()
        .command("version", version)
        .command("status", status)
        .command("setKey", set_key)
        .command("ask", ask)
        .finish()
}

fn version() -> &'static str {
    EXTENSION_VERSION
}

fn status() -> &'static str {
    if key::resolve_key().is_some() { "ok" } else { "nokey" }
}

fn set_key(api_key: String) -> &'static str {
    key::set_runtime_key(&api_key);
    "ok"
}

/// Validates the request, then posts it from a worker thread so the game
/// thread never waits on the network. The answer arrives via the callback.
fn ask(context: Context, id: RequestId, model: String, body: String) -> String {
    if body.len() > MAX_BODY_BYTES {
        return ERROR_TOO_LARGE.to_string();
    }
    let request_body = match jev::complete_body(&body, &model) {
        Ok(request_body) => request_body,
        Err(_) => return ERROR_BAD_JSON.to_string(),
    };
    let Some(api_key) = key::resolve_key() else {
        return ERROR_NO_KEY.to_string();
    };
    let worker = std::thread::Builder::new()
        .name("aic_jev-ask".to_string())
        .spawn(move || {
            let outcome = http::post_with_retry(&api_key, &request_body);
            let data = jev::callback_data(&id, outcome);
            // The only way this fails is the extension being unloaded; nothing to report to.
            let _ = context.callback_data(CALLBACK_NAME, CALLBACK_FUNCTION, data);
        });
    match worker {
        Ok(_) => REPLY_QUEUED.to_string(),
        Err(_) => ERROR_THREAD.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn quoted(text: &str) -> String {
        sqf::escape_string(text)
    }

    #[test]
    fn version_answers_without_arguments() {
        let extension = init().testing();
        let (output, code) = extension.call("version", None);
        assert_eq!(code, 0);
        assert_eq!(output, "1.0.0");
    }

    #[test]
    fn status_reports_ok_or_nokey() {
        let extension = init().testing();
        let (output, code) = extension.call("status", Some(vec![]));
        assert_eq!(code, 0);
        assert!(output == "ok" || output == "nokey", "unexpected status {output}");
    }

    #[test]
    fn set_key_acknowledges() {
        let extension = init().testing();
        let (output, code) = extension.call("setKey", Some(vec![quoted("")]));
        assert_eq!(code, 0);
        assert_eq!(output, "ok");
    }

    #[test]
    fn ask_rejects_oversized_bodies_before_anything_else() {
        let extension = init().testing();
        let huge = format!("{{\"state\":\"{}\"}}", "x".repeat(MAX_BODY_BYTES));
        let (output, code) = extension.call(
            "ask",
            Some(vec!["1".to_string(), quoted("jev-latest"), quoted(&huge)]),
        );
        assert_eq!(code, 0);
        assert_eq!(output, ERROR_TOO_LARGE);
    }

    #[test]
    fn ask_rejects_bodies_that_are_not_json_objects() {
        let extension = init().testing();
        let (output, _) = extension.call(
            "ask",
            Some(vec![quoted("tag"), quoted("jev-latest"), quoted("[1,2,3]")]),
        );
        assert_eq!(output, ERROR_BAD_JSON);
    }

    #[test]
    fn ask_requires_three_arguments() {
        let extension = init().testing();
        let (_, code) = extension.call("ask", Some(vec!["1".to_string()]));
        assert_ne!(code, 0);
    }
}

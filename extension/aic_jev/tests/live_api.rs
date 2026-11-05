//! Live round trip against the real Jev API. Ignored by default; run with
//!
//!     TYPESAFE_API_KEY=... cargo test --test live_api -- --ignored
//!
//! It goes through the extension exactly as Arma would: `ask` is called
//! through the arma-rs test harness and the answer is read from the callback.

use std::time::Duration;

use aic_jev::{CALLBACK_FUNCTION, CALLBACK_NAME, REPLY_QUEUED, jev, sqf};
use arma_rs::{Result as CallbackResult, Value};

const ANSWER_TIMEOUT: Duration = Duration::from_secs(30);
const REQUEST_ID: &str = "42";

#[test]
#[ignore = "needs TYPESAFE_API_KEY and network access"]
fn ask_round_trip() {
    if std::env::var(aic_jev::key::KEY_ENV_VAR).map_or(true, |key| key.trim().is_empty()) {
        eprintln!("{} is not set; skipping", aic_jev::key::KEY_ENV_VAR);
        return;
    }
    let extension = aic_jev::init().testing();
    let body = jev::example_request("jev-latest").to_string();
    let (reply, code) = extension.call(
        "ask",
        Some(vec![
            REQUEST_ID.to_string(),
            sqf::escape_string("jev-latest"),
            sqf::escape_string(&body),
        ]),
    );
    assert_eq!(code, 0);
    assert_eq!(reply, REPLY_QUEUED);

    let answer = extension.callback_handler(
        |name, function, data| {
            assert_eq!(name, CALLBACK_NAME);
            assert_eq!(function, CALLBACK_FUNCTION);
            match data {
                Some(Value::String(text)) => CallbackResult::Ok(text),
                other => CallbackResult::Err(format!("unexpected callback data: {other:?}")),
            }
        },
        ANSWER_TIMEOUT,
    );
    let CallbackResult::Ok(data) = answer else {
        panic!("no callback within {ANSWER_TIMEOUT:?}: {answer:?}");
    };
    eprintln!("callback data: {data}");
    assert!(
        data.starts_with(&format!("[{REQUEST_ID},true,[[\"attack_now\",\"noul\",")),
        "unexpected callback data: {data}"
    );
}

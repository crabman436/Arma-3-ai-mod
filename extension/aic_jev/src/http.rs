//! The HTTPS request to the Jev API: one attempt with a hard timeout, and a
//! single retry after a short pause when the failure looks transient
//! (429, 5xx or a transport error).

use std::sync::OnceLock;
use std::time::Duration;

use ureq::Agent;

use crate::jev::API_URL;

/// Whole-request timeout (connect + send + receive).
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);
/// Pause before the single retry.
pub const RETRY_DELAY: Duration = Duration::from_secs(1);
/// How many times a failed request is retried.
pub const RETRY_COUNT: usize = 1;
/// Error bodies are cut to this many characters in the callback message.
pub const MAX_ERROR_DETAIL_CHARS: usize = 300;

const HTTP_TOO_MANY_REQUESTS: u16 = 429;
const HTTP_FIRST_SERVER_ERROR: u16 = 500;

/// Why a request failed, and whether trying again might help.
#[derive(Debug)]
pub struct RequestFailure {
    pub message: String,
    pub retryable: bool,
}

/// Posts `body` to the API with `api_key`, retrying once on transient failures.
/// Returns the response body on HTTP 2xx, otherwise the error message for the callback.
pub fn post_with_retry(api_key: &str, body: &str) -> Result<String, String> {
    let mut attempts_left = RETRY_COUNT + 1;
    loop {
        attempts_left -= 1;
        match post_once(API_URL, api_key, body) {
            Ok(response) => return Ok(response),
            Err(failure) if failure.retryable && attempts_left > 0 => {
                std::thread::sleep(RETRY_DELAY);
            }
            Err(failure) => return Err(failure.message),
        }
    }
}

/// A single POST. The key only ever goes into the Authorization header.
pub fn post_once(url: &str, api_key: &str, body: &str) -> Result<String, RequestFailure> {
    let response = agent()
        .post(url)
        .header("Authorization", &format!("Bearer {api_key}"))
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .send(body);
    let mut response = match response {
        Ok(response) => response,
        Err(error) => {
            return Err(RequestFailure {
                message: format!("transport: {error}"),
                retryable: true,
            });
        }
    };
    let status = response.status().as_u16();
    let text = match response.body_mut().read_to_string() {
        Ok(text) => text,
        Err(error) => {
            return Err(RequestFailure {
                message: format!("HTTP {status}: unreadable body: {error}"),
                retryable: true,
            });
        }
    };
    if response.status().is_success() {
        return Ok(text);
    }
    Err(RequestFailure {
        message: format!("HTTP {status}: {}", error_detail(&text)),
        retryable: is_transient_status(status),
    })
}

/// 429 and every 5xx are worth one more try; 4xx are not.
pub fn is_transient_status(status: u16) -> bool {
    status == HTTP_TOO_MANY_REQUESTS || status >= HTTP_FIRST_SERVER_ERROR
}

/// Pulls `detail` out of an API error body (`{"detail": ...}`), or falls back
/// to the raw body, truncated to keep the callback small.
pub fn error_detail(body: &str) -> String {
    let detail = serde_json::from_str::<serde_json::Value>(body)
        .ok()
        .and_then(|parsed| parsed.get("detail").cloned())
        .map(|detail| match detail {
            serde_json::Value::String(text) => text,
            other => other.to_string(),
        })
        .unwrap_or_else(|| body.trim().to_string());
    truncate_chars(&detail, MAX_ERROR_DETAIL_CHARS)
}

fn truncate_chars(text: &str, max_chars: usize) -> String {
    if text.chars().count() <= max_chars {
        return text.to_string();
    }
    let mut truncated: String = text.chars().take(max_chars).collect();
    truncated.push_str("...");
    truncated
}

fn agent() -> &'static Agent {
    static AGENT: OnceLock<Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        let config = Agent::config_builder()
            .timeout_global(Some(REQUEST_TIMEOUT))
            .http_status_as_error(false)
            .user_agent(concat!("aic_jev/", env!("CARGO_PKG_VERSION")))
            .build();
        Agent::new_with_config(config)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transient_statuses() {
        assert!(is_transient_status(429));
        assert!(is_transient_status(500));
        assert!(is_transient_status(503));
        assert!(!is_transient_status(400));
        assert!(!is_transient_status(401));
        assert!(!is_transient_status(404));
    }

    #[test]
    fn error_detail_prefers_the_detail_field() {
        assert_eq!(error_detail(r#"{"detail":"Invalid API key"}"#), "Invalid API key");
        assert_eq!(error_detail(r#"{"detail":{"loc":["body"],"msg":"bad"}}"#), r#"{"loc":["body"],"msg":"bad"}"#);
        assert_eq!(error_detail("  <html>502</html> "), "<html>502</html>");
        let long = "x".repeat(MAX_ERROR_DETAIL_CHARS + 50);
        let detail = error_detail(&long);
        assert_eq!(detail.chars().count(), MAX_ERROR_DETAIL_CHARS + 3);
        assert!(detail.ends_with("..."));
    }
}

//! aic_jev: Arma 3 extension that sends the AI Commander's briefings to
//! TypeSafe's Jev decision model and returns the answers to SQF.
//!
//! SQF side (server only):
//!   "aic_jev" callExtension ["version", []]        -> ["0.1.0", 0, 0]
//!   "aic_jev" callExtension ["ready", []]          -> ["ok", 0, 0] or ["no_key", 0, 0]
//!   "aic_jev" callExtension ["ask", [id, model, stateJson, questionsJson]]
//!       -> ["queued", 0, 0] or ["error:<reason>", 0, 0], then later one
//!          ExtensionCallback with name "aic_jev" and function
//!            "answer": [id, [answers...], [latencyMs, inputTokens, model]]
//!            "error":  [id, reason]
//!          (data is SQF array text for parseSimpleArray)
//!
//! The HTTP request runs on its own thread, so the game never waits.
//! The API key is read from the environment (TYPESAFE_API_KEY) or from
//! aic_jev.cfg in the server's working directory; it never passes through
//! SQF.

use arma_rs::{arma, Context, Extension, Value};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

pub const DEFAULT_URL: &str = "https://api.typesafe.ai/v1/systemone";
pub const CONFIG_FILE: &str = "aic_jev.cfg";
/// Requests in flight at once, over all commanders.
const MAX_IN_FLIGHT: usize = 4;
/// Arma's callback buffer is not documented; answers are kept well below
/// the 10240-byte return buffer to be safe.
const MAX_CALLBACK_LEN: usize = 9000;
const MAX_ERROR_LEN: usize = 200;

static IN_FLIGHT: AtomicUsize = AtomicUsize::new(0);

#[arma]
fn init() -> Extension {
    extension()
}

/// The extension definition, shared by the DLL entry point and the tests.
pub fn extension() -> Extension {
    Extension::build()
        .command("version", version)
        .command("ready", ready)
        .command("ask", ask)
        .finish()
}

fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

fn ready() -> &'static str {
    if Config::load().api_key.is_some() {
        "ok"
    } else {
        "no_key"
    }
}

// ------------------------------------------------------------------ config

#[derive(Debug, Clone, PartialEq)]
pub struct Config {
    pub api_key: Option<String>,
    pub api_url: String,
    pub timeout: Duration,
}

impl Config {
    /// File first, then environment variables override it.
    pub fn load() -> Config {
        let file = std::fs::read_to_string(CONFIG_FILE).unwrap_or_default();
        Config::from_sources(&file, |k| std::env::var(k).ok())
    }

    pub fn from_sources(file: &str, env: impl Fn(&str) -> Option<String>) -> Config {
        let mut cfg = Config {
            api_key: None,
            api_url: DEFAULT_URL.to_string(),
            timeout: Duration::from_secs(8),
        };
        for line in file.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((k, v)) = line.split_once('=') else { continue };
            let v = v.trim().trim_matches('"').to_string();
            match k.trim() {
                "api_key" if !v.is_empty() => cfg.api_key = Some(v),
                "api_url" if !v.is_empty() => cfg.api_url = v,
                "timeout_s" => {
                    if let Ok(s) = v.parse::<u64>() {
                        cfg.timeout = Duration::from_secs(s.clamp(1, 60));
                    }
                }
                _ => {}
            }
        }
        if let Some(k) = env("TYPESAFE_API_KEY").filter(|k| !k.is_empty()) {
            cfg.api_key = Some(k);
        }
        if let Some(u) = env("AIC_JEV_URL").filter(|u| !u.is_empty()) {
            cfg.api_url = u;
        }
        cfg
    }
}

// ------------------------------------------------------------------ ask

fn ask(ctx: Context, id: String, model: String, state: String, questions: String) -> String {
    let state: serde_json::Value = match serde_json::from_str(&state) {
        Ok(v) => v,
        Err(e) => return format!("error:bad_state_json {}", short(&e.to_string())),
    };
    let questions = match serde_json::from_str::<serde_json::Value>(&questions) {
        Ok(v) if v.is_object() => v,
        Ok(_) => return "error:questions_not_object".to_string(),
        Err(e) => return format!("error:bad_questions_json {}", short(&e.to_string())),
    };
    let cfg = Config::load();
    let Some(key) = cfg.api_key.clone() else {
        return "error:no_key".to_string();
    };
    if IN_FLIGHT.fetch_add(1, Ordering::SeqCst) >= MAX_IN_FLIGHT {
        IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
        return "error:busy".to_string();
    }

    let body = serde_json::json!({ "model": model, "state": state, "questions": questions });
    std::thread::spawn(move || {
        let started = Instant::now();
        let result = post(&cfg, &key, &body);
        IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
        let latency_ms = started.elapsed().as_millis() as f64;
        // a closed callback channel means the game is shutting down: nothing to tell
        let _ = match result.and_then(|json| compact(&json, latency_ms)) {
            Ok(answer) => ctx.callback_data(
                "aic_jev",
                "answer",
                vec![Value::String(id), answer.0, answer.1],
            ),
            Err(reason) => ctx.callback_data(
                "aic_jev",
                "error",
                vec![Value::String(id), Value::String(short(&reason))],
            ),
        };
    });
    "queued".to_string()
}

/// POST with one retry after 1 s on 429 / 5xx / transport errors.
fn post(cfg: &Config, key: &str, body: &serde_json::Value) -> Result<serde_json::Value, String> {
    let agent = ureq::AgentBuilder::new().timeout(cfg.timeout).build();
    let text = body.to_string();
    let mut last = String::new();
    for attempt in 0..2 {
        if attempt > 0 {
            std::thread::sleep(Duration::from_secs(1));
        }
        let res = agent
            .post(&cfg.api_url)
            .set("Authorization", &format!("Bearer {key}"))
            .set("Content-Type", "application/json")
            .send_string(&text);
        match res {
            Ok(resp) => {
                let raw = resp.into_string().map_err(|e| format!("read: {e}"))?;
                return serde_json::from_str::<serde_json::Value>(&raw)
                    .map_err(|e| format!("bad response json: {e}"));
            }
            Err(ureq::Error::Status(code, resp)) => {
                let detail = resp.into_string().unwrap_or_default();
                last = format!("http {code}: {}", short(&detail));
                if !(code == 429 || code >= 500) {
                    return Err(last);
                }
            }
            Err(e) => last = format!("transport: {e}"),
        }
    }
    Err(last)
}

// ------------------------------------------------------------------ answers

/// Turns a Jev response into ([answers], [latencyMs, inputTokens, model]).
///   noul:   [name, "noul", p]
///   choice: [name, "choice", choice, confidence, [[option, p], ...]]
///   score:  [name, "score", score, confidence]
///   other:  [name, type]
/// Answers are sorted by name. If the result would be too long for a
/// callback, the per-option probabilities are dropped.
pub fn compact(json: &serde_json::Value, latency_ms: f64) -> Result<(Value, Value), String> {
    let answers = json
        .get("answers")
        .and_then(|a| a.as_object())
        .ok_or_else(|| "response has no answers".to_string())?;
    let tokens = json
        .pointer("/usage/input_tokens")
        .and_then(|t| t.as_f64())
        .unwrap_or(-1.0);
    let model = json.get("model").and_then(|m| m.as_str()).unwrap_or("").to_string();
    let meta = Value::Array(vec![
        Value::Number(latency_ms),
        Value::Number(tokens),
        Value::String(model),
    ]);

    let mut names: Vec<&String> = answers.keys().collect();
    names.sort();
    let build = |with_probs: bool| {
        Value::Array(
            names
                .iter()
                .map(|name| compact_one(name, &answers[name.as_str()], with_probs))
                .collect(),
        )
    };
    let mut list = build(true);
    if list.to_string().len() + meta.to_string().len() > MAX_CALLBACK_LEN {
        list = build(false);
    }
    Ok((list, meta))
}

fn compact_one(name: &str, a: &serde_json::Value, with_probs: bool) -> Value {
    let num = |k: &str| Value::Number(a.get(k).and_then(|v| v.as_f64()).unwrap_or(-1.0));
    let kind = a.get("type").and_then(|t| t.as_str()).unwrap_or("").to_string();
    let mut out = vec![Value::String(name.to_string()), Value::String(kind.clone())];
    match kind.as_str() {
        "noul" => out.push(num("noul")),
        "choice" => {
            let choice = a.get("choice").and_then(|c| c.as_str()).unwrap_or("").to_string();
            out.push(Value::String(choice));
            out.push(num("confidence"));
            if with_probs {
                let mut probs: Vec<(String, f64)> = a
                    .get("probabilities")
                    .and_then(|p| p.as_object())
                    .map(|p| {
                        p.iter()
                            .map(|(k, v)| (k.clone(), v.as_f64().unwrap_or(0.0)))
                            .collect()
                    })
                    .unwrap_or_default();
                probs.sort_by(|x, y| y.1.partial_cmp(&x.1).unwrap_or(std::cmp::Ordering::Equal));
                out.push(Value::Array(
                    probs
                        .into_iter()
                        .map(|(k, p)| Value::Array(vec![Value::String(k), Value::Number(round3(p))]))
                        .collect(),
                ));
            }
        }
        "score" => {
            out.push(num("score"));
            out.push(num("confidence"));
        }
        _ => {}
    }
    Value::Array(out)
}

fn round3(x: f64) -> f64 {
    (x * 1000.0).round() / 1000.0
}

fn short(s: &str) -> String {
    let s: String = s.chars().filter(|c| !c.is_control()).collect();
    if s.chars().count() > MAX_ERROR_LEN {
        s.chars().take(MAX_ERROR_LEN).collect::<String>() + "..."
    } else {
        s
    }
}

// ------------------------------------------------------------------ tests

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_file_then_env() {
        let file = "# comment\napi_key = \"from-file\"\ntimeout_s = 3\napi_url=http://x/y\n";
        let none = |_: &str| None;
        let c = Config::from_sources(file, none);
        assert_eq!(c.api_key.as_deref(), Some("from-file"));
        assert_eq!(c.api_url, "http://x/y");
        assert_eq!(c.timeout, Duration::from_secs(3));

        let env = |k: &str| (k == "TYPESAFE_API_KEY").then(|| "from-env".to_string());
        assert_eq!(Config::from_sources(file, env).api_key.as_deref(), Some("from-env"));

        let empty = Config::from_sources("", none);
        assert_eq!(empty.api_key, None);
        assert_eq!(empty.api_url, DEFAULT_URL);
    }

    #[test]
    fn compact_all_types() {
        let json = serde_json::json!({
            "model": "jev-1.14.0",
            "answers": {
                "posture": { "type": "choice", "choice": "DEFENSIVE", "confidence": 0.81,
                             "probabilities": { "OFFENSIVE": 0.05, "BALANCED": 0.14, "DEFENSIVE": 0.81 } },
                "continue_obj_kavala": { "type": "noul", "noul": 0.22 },
                "risk": { "type": "score", "score": 1.7, "confidence": 0.55,
                          "legend": { "0": "a" }, "probabilities": { "0": 0.1 } }
            },
            "usage": { "input_tokens": 912, "output_tokens": 9 }
        });
        let (answers, meta) = compact(&json, 340.0).unwrap();
        assert_eq!(
            answers.to_string(),
            r#"[["continue_obj_kavala","noul",0.22],["posture","choice","DEFENSIVE",0.81,[["DEFENSIVE",0.81],["BALANCED",0.14],["OFFENSIVE",0.05]]],["risk","score",1.7,0.55]]"#
        );
        assert_eq!(meta.to_string(), r#"[340,912,"jev-1.14.0"]"#);
    }

    #[test]
    fn compact_escapes_quotes_for_sqf() {
        let json = serde_json::json!({ "answers": {
            "q": { "type": "choice", "choice": "say \"hi\"", "confidence": 1.0, "probabilities": {} } } });
        let (answers, _) = compact(&json, 1.0).unwrap();
        assert_eq!(answers.to_string(), r#"[["q","choice","say ""hi""",1,[]]]"#);
    }

    #[test]
    fn compact_drops_probabilities_when_too_long() {
        let mut probs = serde_json::Map::new();
        for i in 0..255 {
            probs.insert(format!("option_with_a_long_name_{i}"), serde_json::json!(0.003));
        }
        let mut answers = serde_json::Map::new();
        for q in 0..4 {
            answers.insert(
                format!("q{q}"),
                serde_json::json!({ "type": "choice", "choice": "option_with_a_long_name_1",
                                    "confidence": 0.3, "probabilities": probs.clone() }),
            );
        }
        let json = serde_json::json!({ "answers": answers });
        let (answers, meta) = compact(&json, 1.0).unwrap();
        assert!(answers.to_string().len() + meta.to_string().len() <= MAX_CALLBACK_LEN);
        assert!(answers.to_string().starts_with(r#"[["q0","choice","option_with_a_long_name_1",0.3]"#));
    }

    #[test]
    fn missing_answers_is_an_error() {
        assert!(compact(&serde_json::json!({ "detail": "x" }), 1.0).is_err());
    }
}

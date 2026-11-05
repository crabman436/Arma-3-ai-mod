//! Jev (TypeSafe System One) specifics: completing the request body and
//! turning the API's JSON answer into the SQF callback payload.
//!
//! Response envelope (verified 2026-11-03):
//! `{"model": "...", "answers": {<qid>: <answer>}, "usage": {...}}` where an
//! answer is one of
//! - `{"type":"noul","noul":p}`
//! - `{"type":"choice","choice":"<key>","confidence":c,"probabilities":{key:p}}`
//! - `{"type":"score","score":s,"confidence":c,"legend":{...},"probabilities":{"0":p,...}}`

use serde_json::{Map, Value};

use crate::sqf::{RequestId, escape_string, format_array, format_bool, format_number, single_line};

/// The System One endpoint.
pub const API_URL: &str = "https://api.typesafe.ai/v1/systemone";

/// Parses `body` as a JSON object and fills in `"model"` from `model` when the
/// body has none. Returns the (re-serialised) body to send.
pub fn complete_body(body: &str, model: &str) -> Result<String, String> {
    let mut parsed: Value =
        serde_json::from_str(body).map_err(|error| format!("body is not valid JSON: {error}"))?;
    let object = parsed
        .as_object_mut()
        .ok_or_else(|| "body must be a JSON object".to_string())?;
    let has_model = object.get("model").is_some_and(|value| !value.is_null());
    if !has_model && !model.trim().is_empty() {
        object.insert("model".to_string(), Value::String(model.trim().to_string()));
    }
    serde_json::to_string(&parsed).map_err(|error| error.to_string())
}

/// Builds the complete callback data `[id, ok, payload]` from the HTTP outcome:
/// `Ok(response body)` or `Err(error message)`.
pub fn callback_data(id: &RequestId, outcome: Result<String, String>) -> String {
    let (ok, payload) = match outcome.and_then(|body| payload_from_response(&body)) {
        Ok(payload) => (true, payload),
        Err(message) => (false, escape_string(&single_line(&message))),
    };
    format_array(&[id.to_sqf(), format_bool(ok).to_string(), payload])
}

/// Converts a successful response body into the SQF payload array
/// `[[qid, type, value, confidence, probsArray], ...]`.
pub fn payload_from_response(body: &str) -> Result<String, String> {
    let parsed: Value = serde_json::from_str(body)
        .map_err(|error| format!("malformed response: {error}"))?;
    let answers = parsed
        .get("answers")
        .and_then(Value::as_object)
        .ok_or_else(|| "malformed response: no \"answers\" object".to_string())?;
    let entries: Vec<String> = answers
        .iter()
        .map(|(qid, answer)| answer_entry(qid, answer))
        .collect();
    Ok(format_array(&entries))
}

/// One `[qid, type, value, confidence, probsArray]` entry.
fn answer_entry(qid: &str, answer: &Value) -> String {
    let kind = answer.get("type").and_then(Value::as_str).unwrap_or("");
    let (value, confidence, probabilities) = match kind {
        "noul" => {
            let probability = number_or_zero(answer.get("noul"));
            (
                format_number(probability),
                noul_confidence(probability),
                vec![
                    ("true".to_string(), probability),
                    ("false".to_string(), 1.0 - probability),
                ],
            )
        }
        "choice" => (
            escape_string(answer.get("choice").and_then(Value::as_str).unwrap_or("")),
            number_or_zero(answer.get("confidence")),
            probabilities_of(answer.get("probabilities")),
        ),
        "score" => (
            format_number(number_or_zero(answer.get("score"))),
            number_or_zero(answer.get("confidence")),
            probabilities_of(answer.get("probabilities")),
        ),
        _ => (escape_string(""), 0.0, Vec::new()),
    };
    let probabilities_array = format_array(
        &probabilities
            .iter()
            .map(|(key, probability)| {
                format_array(&[escape_string(key), format_number(*probability)])
            })
            .collect::<Vec<_>>(),
    );
    format_array(&[
        escape_string(qid),
        escape_string(kind),
        value,
        format_number(confidence),
        probabilities_array,
    ])
}

/// A noul answer is a probability `p`; `|2p - 1|` is 0 at "coin flip" and 1 at certainty.
pub fn noul_confidence(probability: f64) -> f64 {
    (2.0 * probability - 1.0).abs()
}

fn number_or_zero(value: Option<&Value>) -> f64 {
    value.and_then(Value::as_f64).unwrap_or(0.0)
}

/// Flattens a `{key: p}` object into ordered pairs. Numeric keys (score
/// levels) are ordered numerically, other keys alphabetically.
fn probabilities_of(value: Option<&Value>) -> Vec<(String, f64)> {
    let Some(object) = value.and_then(Value::as_object) else {
        return Vec::new();
    };
    let mut pairs: Vec<(String, f64)> = object
        .iter()
        .map(|(key, probability)| (key.clone(), probability.as_f64().unwrap_or(0.0)))
        .collect();
    pairs.sort_by_key(|(key, _)| key_order(key));
    pairs
}

fn key_order(key: &str) -> (bool, Option<i64>, String) {
    match key.parse::<f64>() {
        Ok(number) => (false, Some((number * 1000.0) as i64), key.to_string()),
        Err(_) => (true, None, key.to_string()),
    }
}

/// Used by tests and the integration test to build a minimal request.
pub fn example_request(model: &str) -> Value {
    let mut questions = Map::new();
    questions.insert(
        "attack_now".to_string(),
        serde_json::json!({"type": "noul", "instructions": "Should the attack be launched now?"}),
    );
    serde_json::json!({
        "model": model,
        "state": "Own power 12, enemy power 4, daylight, intel 30 s old, reserve at base.",
        "questions": questions,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The quickstart example from docs.typesafe.ai, plus the contract's per-type shapes.
    const SAMPLE_RESPONSE: &str = r#"{
        "model": "jev-1.13.0",
        "answers": {
            "department": {
                "type": "choice",
                "choice": "technical",
                "confidence": 1.0,
                "probabilities": {"technical": 1.0, "billing": 0.0, "sales": 0.0}
            },
            "frustration": {
                "type": "score",
                "score": 0.67,
                "confidence": 0.5,
                "legend": {"0": "Calm, just stating facts", "1": "Frustrated but civil", "2": "Very angry, strong language"},
                "probabilities": {"0": 0.33, "1": 0.67, "2": 0.0}
            },
            "is_urgent": {"type": "noul", "noul": 0.99}
        },
        "usage": {"input_tokens": 428, "output_tokens": 73}
    }"#;

    #[test]
    fn parses_the_documented_response_into_sqf_payload() {
        let payload = payload_from_response(SAMPLE_RESPONSE).unwrap();
        assert_eq!(
            payload,
            concat!(
                "[",
                "[\"department\",\"choice\",\"technical\",1,[[\"billing\",0],[\"sales\",0],[\"technical\",1]]],",
                "[\"frustration\",\"score\",0.67,0.5,[[\"0\",0.33],[\"1\",0.67],[\"2\",0]]],",
                "[\"is_urgent\",\"noul\",0.99,0.98,[[\"true\",0.99],[\"false\",0.01]]]",
                "]"
            )
        );
    }

    #[test]
    fn noul_confidence_is_distance_from_coin_flip() {
        assert_eq!(noul_confidence(0.5), 0.0);
        assert_eq!(noul_confidence(1.0), 1.0);
        assert_eq!(noul_confidence(0.0), 1.0);
        assert!((noul_confidence(0.75) - 0.5).abs() < 1e-9);
    }

    #[test]
    fn null_confidence_becomes_zero_and_unknown_types_are_kept() {
        let body = r#"{"answers":{
            "posture":{"type":"choice","choice":"offensive","confidence":null,"probabilities":{"offensive":0.6,"balanced":0.3,"defensive":0.1}},
            "risk":{"type":"score","score":2.25,"confidence":null,"probabilities":{"0":0.0,"1":0.1,"2":0.55,"3":0.35,"10":0.0}},
            "mystery":{"type":"future","whatever":1}
        }}"#;
        let payload = payload_from_response(body).unwrap();
        assert_eq!(
            payload,
            concat!(
                "[",
                "[\"mystery\",\"future\",\"\",0,[]],",
                "[\"posture\",\"choice\",\"offensive\",0,[[\"balanced\",0.3],[\"defensive\",0.1],[\"offensive\",0.6]]],",
                "[\"risk\",\"score\",2.25,0,[[\"0\",0],[\"1\",0.1],[\"2\",0.55],[\"3\",0.35],[\"10\",0]]]",
                "]"
            )
        );
    }

    #[test]
    fn quotes_in_keys_are_escaped() {
        let body = r#"{"answers":{"q \"1\"":{"type":"choice","choice":"say \"go\"","confidence":0.4,"probabilities":{"say \"go\"":0.4,"wait":0.6}}}}"#;
        let payload = payload_from_response(body).unwrap();
        assert_eq!(
            payload,
            "[[\"q \"\"1\"\"\",\"choice\",\"say \"\"go\"\"\",0.4,[[\"say \"\"go\"\"\",0.4],[\"wait\",0.6]]]]"
        );
    }

    #[test]
    fn malformed_responses_are_reported() {
        assert!(payload_from_response("not json").unwrap_err().starts_with("malformed response"));
        assert_eq!(
            payload_from_response(r#"{"detail":"oops"}"#).unwrap_err(),
            "malformed response: no \"answers\" object"
        );
    }

    #[test]
    fn callback_data_wraps_success_and_failure() {
        let id = RequestId::Number(3.0);
        let success = callback_data(&id, Ok(r#"{"answers":{"a":{"type":"noul","noul":0.5}}}"#.to_string()));
        assert_eq!(success, "[3,true,[[\"a\",\"noul\",0.5,0,[[\"true\",0.5],[\"false\",0.5]]]]]");

        let text_id = RequestId::Text("tag".to_string());
        let failure = callback_data(&text_id, Err("HTTP 401: {\"detail\":\"bad key\"}\n".to_string()));
        assert_eq!(failure, "[\"tag\",false,\"HTTP 401: {\"\"detail\"\":\"\"bad key\"\"}\"]");

        let unparsable = callback_data(&id, Ok("<html>".to_string()));
        assert!(unparsable.starts_with("[3,false,\"malformed response"));
    }

    #[test]
    fn complete_body_fills_missing_model_only() {
        let completed = complete_body(r#"{"state":"x","questions":{}}"#, "jev-latest").unwrap();
        let parsed: Value = serde_json::from_str(&completed).unwrap();
        assert_eq!(parsed["model"], "jev-latest");

        let kept = complete_body(r#"{"model":"jev-1","state":"x","questions":{}}"#, "jev-latest").unwrap();
        let parsed: Value = serde_json::from_str(&kept).unwrap();
        assert_eq!(parsed["model"], "jev-1");

        assert!(complete_body("[1,2]", "jev-latest").is_err());
        assert!(complete_body("{not json", "jev-latest").is_err());
    }
}

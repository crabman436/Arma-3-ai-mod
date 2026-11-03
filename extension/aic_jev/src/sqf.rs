//! Formatting values as SQF literals that `parseSimpleArray` reads back,
//! and parsing the request id Arma hands to `ask`.

use arma_rs::{FromArma, FromArmaError};

/// Numbers are rounded to this many decimals before trailing zeros are trimmed.
/// SQF numbers are 32-bit floats, so more precision would be noise.
pub const DECIMAL_PLACES: usize = 6;

/// Wraps `text` in double quotes and doubles every embedded double quote,
/// which is how SQF escapes strings.
pub fn escape_string(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len() + 2);
    escaped.push('"');
    for character in text.chars() {
        if character == '"' {
            escaped.push_str("\"\"");
        } else {
            escaped.push(character);
        }
    }
    escaped.push('"');
    escaped
}

/// Formats a number plainly: never exponent notation, no trailing zeros,
/// no trailing dot, and `-0` collapses to `0`. Non-finite values become `0`.
pub fn format_number(value: f64) -> String {
    if !value.is_finite() {
        return "0".to_string();
    }
    let fixed = format!("{value:.DECIMAL_PLACES$}");
    let trimmed = fixed.trim_end_matches('0').trim_end_matches('.');
    if trimmed == "-0" {
        "0".to_string()
    } else {
        trimmed.to_string()
    }
}

/// SQF boolean literal.
pub fn format_bool(value: bool) -> &'static str {
    if value { "true" } else { "false" }
}

/// Joins already formatted SQF items into an SQF array literal.
pub fn format_array(items: &[String]) -> String {
    format!("[{}]", items.join(","))
}

/// Collapses control characters (newlines, tabs, ...) into single spaces so an
/// error message stays on one line inside the callback data.
pub fn single_line(text: &str) -> String {
    text.chars()
        .map(|character| if character.is_control() { ' ' } else { character })
        .collect::<String>()
        .trim()
        .to_string()
}

/// The `id` the SQF side passes to `ask`: either a number or a string.
/// It is echoed back unchanged in the callback so the caller can match answers.
#[derive(Debug, Clone, PartialEq)]
pub enum RequestId {
    Number(f64),
    Text(String),
}

impl RequestId {
    /// Formats the id as the SQF literal it came from.
    pub fn to_sqf(&self) -> String {
        match self {
            RequestId::Number(value) => format_number(*value),
            RequestId::Text(text) => escape_string(text),
        }
    }
}

impl FromArma for RequestId {
    /// Arma passes extension arguments in SQF literal form: strings arrive
    /// quoted with `""` escapes, numbers arrive bare.
    fn from_arma(raw: String) -> Result<Self, FromArmaError> {
        let trimmed = raw.trim();
        if let Some(inner) = trimmed
            .strip_prefix('"')
            .and_then(|rest| rest.strip_suffix('"'))
        {
            return Ok(RequestId::Text(inner.replace("\"\"", "\"")));
        }
        trimmed
            .parse::<f64>()
            .map(RequestId::Number)
            .map_err(|_| FromArmaError::InvalidPrimitive("id must be a string or a number".to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escape_string_doubles_quotes_and_wraps() {
        assert_eq!(escape_string("plain"), "\"plain\"");
        assert_eq!(escape_string(""), "\"\"");
        assert_eq!(escape_string("say \"hi\""), "\"say \"\"hi\"\"\"");
        assert_eq!(escape_string("back\\slash"), "\"back\\slash\"");
        assert_eq!(escape_string("ünïcödé ✓"), "\"ünïcödé ✓\"");
    }

    #[test]
    fn format_number_is_plain_and_trimmed() {
        assert_eq!(format_number(0.0), "0");
        assert_eq!(format_number(-0.0), "0");
        assert_eq!(format_number(1.0), "1");
        assert_eq!(format_number(0.5), "0.5");
        assert_eq!(format_number(0.73), "0.73");
        assert_eq!(format_number(0.1 + 0.2), "0.3");
        assert_eq!(format_number(1234567.0), "1234567");
        assert_eq!(format_number(1e9), "1000000000");
        assert_eq!(format_number(1e-7), "0");
        assert_eq!(format_number(-2.5), "-2.5");
        assert_eq!(format_number(f64::NAN), "0");
        assert_eq!(format_number(f64::INFINITY), "0");
    }

    #[test]
    fn format_array_and_bool() {
        assert_eq!(format_array(&[]), "[]");
        assert_eq!(
            format_array(&["1".to_string(), "true".to_string(), "\"x\"".to_string()]),
            "[1,true,\"x\"]"
        );
        assert_eq!(format_bool(true), "true");
        assert_eq!(format_bool(false), "false");
    }

    #[test]
    fn single_line_flattens_control_characters() {
        assert_eq!(single_line("  HTTP 400:\n{\"detail\":\t\"bad\"}\r\n"), "HTTP 400: {\"detail\":  \"bad\"}");
    }

    #[test]
    fn request_id_parses_numbers_and_strings() {
        assert_eq!(RequestId::from_arma("7".to_string()).unwrap(), RequestId::Number(7.0));
        assert_eq!(RequestId::from_arma(" 12.5 ".to_string()).unwrap(), RequestId::Number(12.5));
        assert_eq!(RequestId::from_arma("1e+06".to_string()).unwrap(), RequestId::Number(1_000_000.0));
        assert_eq!(
            RequestId::from_arma("\"advisor_west\"".to_string()).unwrap(),
            RequestId::Text("advisor_west".to_string())
        );
        assert_eq!(
            RequestId::from_arma("\"a \"\"quoted\"\" id\"".to_string()).unwrap(),
            RequestId::Text("a \"quoted\" id".to_string())
        );
        assert!(RequestId::from_arma("not a number".to_string()).is_err());
    }

    #[test]
    fn request_id_round_trips_to_sqf() {
        assert_eq!(RequestId::Number(7.0).to_sqf(), "7");
        assert_eq!(RequestId::Number(1_000_000.0).to_sqf(), "1000000");
        assert_eq!(RequestId::Text("a \"b\"".to_string()).to_sqf(), "\"a \"\"b\"\"\"");
    }
}

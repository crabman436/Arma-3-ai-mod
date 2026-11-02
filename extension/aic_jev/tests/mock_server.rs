//! End to end: the extension, driven like Arma drives it, against a fake
//! Jev server on localhost. One test function, because it sets process-wide
//! environment variables.

use arma_rs::Value;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::sync::mpsc;
use std::time::Duration;

/// Serves `responses` in order, one per connection, and sends each request
/// (headers + body) back through the channel.
fn fake_jev(responses: Vec<(u16, String)>) -> (String, mpsc::Receiver<String>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/v1/systemone", listener.local_addr().unwrap());
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        for (status, body) in responses {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut head = String::new();
            let mut len = 0usize;
            loop {
                let mut line = String::new();
                reader.read_line(&mut line).unwrap();
                if line.to_ascii_lowercase().starts_with("content-length:") {
                    len = line[15..].trim().parse().unwrap();
                }
                head.push_str(&line);
                if line == "\r\n" {
                    break;
                }
            }
            let mut req_body = vec![0u8; len];
            reader.read_exact(&mut req_body).unwrap();
            tx.send(head + &String::from_utf8(req_body).unwrap()).unwrap();
            let mut stream = stream;
            write!(
                stream,
                "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            )
            .unwrap();
        }
    });
    (url, rx)
}

/// SQF string literal, as Arma passes callExtension arguments.
fn sqf(s: &str) -> String {
    format!("\"{}\"", s.replace('"', "\"\""))
}

fn ask(ext: &arma_rs::testing::Extension, id: &str, state: &str, questions: &str) -> String {
    let args = vec![sqf(id), sqf("jev-1.14.0"), sqf(state), sqf(questions)];
    ext.call("ask", Some(args)).0
}

fn next_callback(ext: &arma_rs::testing::Extension) -> (String, String, String) {
    let result = ext.callback_handler(
        |name, func, data| -> arma_rs::testing::Result<(String, String, String), ()> {
            // the same text Arma receives as the callback's data
            let data = match data {
                Some(Value::String(s)) => s,
                Some(v) => v.to_string(),
                None => String::new(),
            };
            arma_rs::testing::Result::Ok((name.to_string(), func.to_string(), data))
        },
        Duration::from_secs(10),
    );
    match result {
        arma_rs::testing::Result::Ok(v) => v,
        _ => panic!("no callback"),
    }
}

#[test]
fn ask_round_trip() {
    let ok = r#"{"model":"jev-1.14.0","answers":{"posture":{"type":"choice","choice":"DEFENSIVE","confidence":0.81,"probabilities":{"DEFENSIVE":0.81,"BALANCED":0.19}}},"usage":{"input_tokens":512,"output_tokens":3}}"#;
    let (url, requests) = fake_jev(vec![
        (200, ok.to_string()),
        (503, r#"{"detail":"busy"}"#.to_string()),
        (200, ok.to_string()),
        (400, r#"{"detail":"unknown model"}"#.to_string()),
    ]);
    std::env::set_var("TYPESAFE_API_KEY", "test-key");
    std::env::set_var("AIC_JEV_URL", &url);

    let ext = aic_jev::extension().testing();
    assert_eq!(ext.call("version", None).0, env!("CARGO_PKG_VERSION"));
    assert_eq!(ext.call("ready", None).0, "ok");

    let state = r#"{"side":"OPFOR","note":"say \"hold\""}"#;
    let questions = r#"{"posture":{"type":"choice","criteria":{"OFFENSIVE":null,"DEFENSIVE":null}}}"#;

    // 1. success
    assert_eq!(ask(&ext, "east-1", state, questions), "queued");
    let req = requests.recv_timeout(Duration::from_secs(10)).unwrap();
    assert!(req.starts_with("POST /v1/systemone"), "{req}");
    assert!(req.to_ascii_lowercase().contains("authorization: bearer test-key"), "{req}");
    let body: serde_json::Value = serde_json::from_str(req.split("\r\n\r\n").nth(1).unwrap()).unwrap();
    assert_eq!(body["model"], "jev-1.14.0");
    assert_eq!(body["state"]["note"], "say \"hold\"");
    assert_eq!(body["questions"]["posture"]["type"], "choice");
    let (name, func, data) = next_callback(&ext);
    assert_eq!((name.as_str(), func.as_str()), ("aic_jev", "answer"));
    assert!(
        data.starts_with(r#"["east-1",[["posture","choice","DEFENSIVE",0.81,[["DEFENSIVE",0.81],["BALANCED",0.19]]]],["#),
        "{data}"
    );
    assert!(data.ends_with(r#",512,"jev-1.14.0"]]"#), "{data}");

    // 2. 503 then success on the retry
    assert_eq!(ask(&ext, "east-2", state, questions), "queued");
    let _ = requests.recv_timeout(Duration::from_secs(10)).unwrap();
    let _ = requests.recv_timeout(Duration::from_secs(10)).unwrap();
    let (_, func, data) = next_callback(&ext);
    assert_eq!(func, "answer");
    assert!(data.starts_with(r#"["east-2","#), "{data}");

    // 3. 400 is not retried and comes back as an error callback
    assert_eq!(ask(&ext, "east-3", state, questions), "queued");
    let _ = requests.recv_timeout(Duration::from_secs(10)).unwrap();
    let (_, func, data) = next_callback(&ext);
    assert_eq!(func, "error");
    assert!(data.starts_with(r#"["east-3","http 400: "#), "{data}");

    // 4. bad input is refused at once, nothing is sent
    assert!(ask(&ext, "east-4", "not json", questions).starts_with("error:bad_state_json"));
    assert_eq!(ask(&ext, "east-5", state, "[1]"), "error:questions_not_object");

    // 5. without a key nothing is sent
    std::env::remove_var("TYPESAFE_API_KEY");
    assert_eq!(ext.call("ready", None).0, "no_key");
    assert_eq!(ask(&ext, "east-6", state, questions), "error:no_key");
}

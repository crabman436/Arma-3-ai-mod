//! API key lookup. Order: `setKey` value, then the `TYPESAFE_API_KEY`
//! environment variable, then the `aic_jev.key` file in the working directory.
//! The key is never logged or echoed back to Arma.

use std::path::Path;
use std::sync::Mutex;

/// Environment variable consulted after `setKey`.
pub const KEY_ENV_VAR: &str = "TYPESAFE_API_KEY";
/// File (one line, relative to the game's working directory) consulted last.
pub const KEY_FILE_NAME: &str = "aic_jev.key";

/// The key set at runtime through `setKey`. Overrides the environment and the file.
static RUNTIME_KEY: Mutex<Option<String>> = Mutex::new(None);

/// Stores (or, for an empty value, clears) the runtime key.
pub fn set_runtime_key(key: &str) {
    let mut slot = RUNTIME_KEY.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    *slot = non_empty(key);
}

/// Resolves the key to use for the next request, following the lookup order.
pub fn resolve_key() -> Option<String> {
    let runtime = || RUNTIME_KEY.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).clone();
    let environment = || std::env::var(KEY_ENV_VAR).ok();
    let file = || read_key_file(Path::new(KEY_FILE_NAME));
    choose_key(&[&runtime, &environment, &file])
}

/// Returns the first source that yields a non-blank key. Sources are only
/// consulted until one succeeds, so the file is not read when `setKey` was used.
pub fn choose_key(sources: &[&dyn Fn() -> Option<String>]) -> Option<String> {
    sources
        .iter()
        .find_map(|source| source().and_then(|candidate| non_empty(&candidate)))
}

/// Reads the key file; missing or unreadable file means "no key".
pub fn read_key_file(path: &Path) -> Option<String> {
    std::fs::read_to_string(path).ok().and_then(|contents| non_empty(&contents))
}

fn non_empty(candidate: &str) -> Option<String> {
    let trimmed = candidate.trim();
    if trimmed.is_empty() { None } else { Some(trimmed.to_string()) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    #[test]
    fn choose_key_prefers_runtime_then_env_then_file() {
        let runtime = || Some("runtime-key".to_string());
        let environment = || Some("env-key".to_string());
        let file = || Some("file-key\n".to_string());
        assert_eq!(choose_key(&[&runtime, &environment, &file]), Some("runtime-key".to_string()));

        let no_runtime = || None;
        assert_eq!(choose_key(&[&no_runtime, &environment, &file]), Some("env-key".to_string()));

        let blank_environment = || Some("   ".to_string());
        assert_eq!(choose_key(&[&no_runtime, &blank_environment, &file]), Some("file-key".to_string()));

        let no_file = || None;
        assert_eq!(choose_key(&[&no_runtime, &blank_environment, &no_file]), None);
    }

    #[test]
    fn choose_key_stops_at_the_first_hit() {
        let file_reads = Cell::new(0);
        let runtime = || Some("runtime-key".to_string());
        let file = || {
            file_reads.set(file_reads.get() + 1);
            Some("file-key".to_string())
        };
        assert_eq!(choose_key(&[&runtime, &file]), Some("runtime-key".to_string()));
        assert_eq!(file_reads.get(), 0);
    }

    #[test]
    fn runtime_key_can_be_set_and_cleared() {
        set_runtime_key("  abc123  ");
        let stored = RUNTIME_KEY.lock().unwrap().clone();
        assert_eq!(stored, Some("abc123".to_string()));
        set_runtime_key("");
        assert_eq!(RUNTIME_KEY.lock().unwrap().clone(), None);
    }

    #[test]
    fn read_key_file_trims_and_ignores_missing() {
        let dir = std::env::temp_dir().join(format!("aic_jev_key_test_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(KEY_FILE_NAME);
        std::fs::write(&path, "  secret-from-file \r\n").unwrap();
        assert_eq!(read_key_file(&path), Some("secret-from-file".to_string()));
        std::fs::write(&path, "\n").unwrap();
        assert_eq!(read_key_file(&path), None);
        std::fs::remove_dir_all(&dir).unwrap();
        assert_eq!(read_key_file(&path), None);
    }
}

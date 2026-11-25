use crate::args::Res;
use std::process::Command;
use std::{env, fs, path::PathBuf};

/// Model used for naming branches.
const BRANCH_MODEL: &str = "github-copilot/claude-haiku-5.5";
const SYSTEM_PROMPT: &str = include_str!("../generate-branch-name.md");

pub fn pi_settings() -> serde_json::Value {
    let dir = env::var_os("PI_CODING_AGENT_DIR")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|h| PathBuf::from(h).join(".pi/agent")));
    dir.and_then(|d| fs::read_to_string(d.join("settings.json")).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(serde_json::Value::Null)
}

/// Reduces the model's reply to a branch name, or None when it is not one.
fn clean(reply: &str) -> Option<String> {
    let line = reply.lines().map(str::trim).rfind(|l| !l.is_empty())?;
    let name = line.trim_matches(|c: char| matches!(c, '`' | '"' | '\'' | '.')).to_lowercase();
    let valid = name.split('/').count() == 2
        && name.split('/').all(|part| {
            !part.is_empty()
                && !part.starts_with('-')
                && !part.ends_with('-')
                && part.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        });
    valid.then_some(name)
}

/// Asks a small pi model for a branch name describing `prompt`.
pub fn generate_branch_name(prompt: &str) -> Res<String> {
    eprintln!("Generating branch name with {BRANCH_MODEL}.");
    let out = Command::new("pi")
        .args(["--print", "--no-session", "--no-tools", "--no-extensions", "--no-skills"])
        .args(["--no-prompt-templates", "--no-context-files", "--no-mcp", "--no-approve"])
        .args(["--model", BRANCH_MODEL, "--thinking", "low", "--system-prompt", SYSTEM_PROMPT, "--"])
        .arg(prompt)
        .output()
        .map_err(|e| format!("cannot run pi: {e}"))?;
    if !out.status.success() {
        eprint!("{}", String::from_utf8_lossy(&out.stderr));
        return Err("pi could not generate a branch name".into());
    }
    let reply = String::from_utf8_lossy(&out.stdout);
    clean(&reply).ok_or_else(|| format!("pi did not return a branch name: {}", reply.trim()))
}

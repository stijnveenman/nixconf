use crate::args::{normalize_branch, Options, Res};
use crate::pi::generate_branch_name;
use serde_json::Value;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use std::{env, fs, thread};

struct Out {
    ok: bool,
    stdout: String,
    stderr: String,
}

fn run(cmd: &str, args: &[&str], pass_stderr: bool) -> Res<Out> {
    let output = Command::new(cmd)
        .args(args)
        .stdin(Stdio::null())
        .stderr(if pass_stderr { Stdio::inherit() } else { Stdio::piped() })
        .output()
        .map_err(|e| format!("cannot run {cmd}: {e}"))?;
    Ok(Out {
        ok: output.status.success(),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    })
}

fn ok(cmd: &str, args: &[&str], pass_stderr: bool) -> Res<String> {
    let r = run(cmd, args, pass_stderr)?;
    if !r.ok {
        eprint!("{}", r.stderr);
        return Err(format!("{cmd} {} failed", args.iter().take(2).copied().collect::<Vec<_>>().join(" ")));
    }
    Ok(r.stdout)
}

/// Returns the non-empty string found at `path` in the JSON text.
fn need(text: &str, what: &str, path: &[&str]) -> Res<String> {
    let mut v: Option<Value> = serde_json::from_str(text).ok();
    for key in path {
        v = v.and_then(|v| v.get(*key).cloned());
    }
    match v {
        Some(Value::String(s)) if !s.is_empty() => Ok(s),
        _ => Err(format!("missing {what}")),
    }
}

fn info(message: &str) {
    eprintln!("{message}");
}

pub fn start(o: Options) -> Res<()> {
    let mut prompt_file = o.prompt_file;
    if let Some(dir) = &o.working_dir {
        if !dir.is_dir() {
            return Err(format!("working directory does not exist: {}", dir.display()));
        }
        // Resolve a relative prompt file before changing directory.
        if let Some(file) = &prompt_file {
            prompt_file = Some(env::current_dir().map_err(|e| e.to_string())?.join(file));
        }
        env::set_current_dir(dir).map_err(|e| e.to_string())?;
    }
    let mut prompt = o.prompt.unwrap_or_default();
    if o.fix {
        let fix = "fix the pr's failed ci checks, push to the upstream, and disable auto-merge if enabled";
        // --prompt adds steering after the fixed instructions.
        prompt = if prompt.is_empty() { fix.into() } else { format!("{fix}\n\n{prompt}") };
    }
    let mut branch = match o.pr {
        Some(pr) => {
            let pr = pr.to_string();
            let r = run("gh", &["pr", "view", &pr, "--json", "headRefName", "--jq", ".headRefName"], false)?;
            if !r.ok {
                return Err(format!("cannot look up PR #{pr}"));
            }
            let branch = r.stdout.trim().to_string();
            if branch.is_empty() {
                return Err(format!("PR #{pr} has no head branch"));
            }
            branch
        }
        None => o.branch.as_deref().map(normalize_branch).unwrap_or_default(),
    };
    if let Some(file) = &prompt_file {
        prompt = fs::read_to_string(file)
            .map_err(|_| format!("cannot read prompt file: {}", file.display()))?;
        if prompt.is_empty() {
            return Err(format!("prompt file is empty: {}", file.display()));
        }
    }
    if branch.is_empty() && o.auto_branch {
        if prompt.is_empty() {
            return Err("an automatic branch name needs a prompt".into());
        }
        let name = generate_branch_name(&prompt)?;
        // Never reuse an existing branch: wt would switch to it instead of creating one.
        let exists = |b: &str| run("git", &["show-ref", "--verify", "--quiet", &format!("refs/heads/{b}")], false).map(|r| r.ok);
        branch = name.clone();
        let mut n = 2;
        while exists(&branch)? {
            branch = format!("{name}-{n}");
            n += 1;
        }
        info(&format!("Using branch {branch}."));
    }
    ok("git", &["check-ref-format", "--branch", &branch], false)?;

    // Resolve repository identity from cwd, never from whichever workspace is focused.
    let cwd = env::current_dir().map_err(|e| e.to_string())?;
    let listed = ok("herdr", &["worktree", "list", "--cwd", &cwd.to_string_lossy()], false)?;
    let repo_root = need(&listed, "repo root", &["result", "source", "repo_root"])?;

    let mut args: Vec<String> = ["switch", "--no-cd", "--format=json"].map(String::from).into();
    let target;
    if let Some(pr) = o.pr {
        // Worktrunk fetches the PR head (including forks) via the pr: shortcut.
        target = format!("pr:{pr}");
    } else {
        target = branch.clone();
        let exists = run("git", &["show-ref", "--verify", "--quiet", &format!("refs/heads/{branch}")], false)?;
        if !exists.ok {
            args.push("--create".into());
        }
    }
    // Worktrunk resolves and validates bases, including shortcuts such as pr:123.
    if let Some(base) = &o.base {
        args.push("--base".into());
        args.push(base.clone());
    }
    args.push(target);
    let refs: Vec<&str> = args.iter().map(String::as_str).collect();
    let checkout = need(&ok("wt", &refs, true)?, "worktree path", &["path"])?;

    // Opening via the primary checkout nests the workspace under the correct repo,
    // including when this command was invoked inside another linked worktree.
    let opened = ok(
        "herdr",
        &["worktree", "open", "--cwd", &repo_root, "--path", &checkout, "--label", &branch, "--no-focus"],
        false,
    )?;
    let workspace = need(&opened, "workspace id", &["result", "workspace", "workspace_id"])?;
    let root_pane = need(&opened, "root pane", &["result", "root_pane", "pane_id"])?;

    // Always use a new pane: an existing workspace may have a busy root terminal.
    let split = ok(
        "herdr",
        &["pane", "split", &root_pane, "--direction", "right", "--cwd", &checkout, "--no-focus"],
        false,
    )?;
    let pane = need(&split, "pane id", &["result", "pane", "pane_id"])?;
    let sanitized: String = pane.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect();
    let name: String = format!("pi-{sanitized}").to_lowercase().chars().take(32).collect();

    let mut start_args = vec!["agent", "start", &name, "--kind", "pi", "--pane", &pane, "--timeout", "60000"];
    let mut agent_flags: Vec<&str> = Vec::new();
    if let Some(model) = &o.model {
        agent_flags.extend(["--model", model]);
    }
    if let Some(effort) = &o.effort {
        agent_flags.extend(["--thinking", effort]);
    }
    if !agent_flags.is_empty() {
        start_args.push("--");
        start_args.extend(agent_flags);
    }
    // A new pane is busy while shell init runs (e.g. direnv evaluating a flake for
    // a fresh checkout). Herdr rejects the start before sending input, so retry.
    let deadline = Instant::now() + Duration::from_secs(300);
    let mut announced = false;
    loop {
        let r = run("herdr", &start_args, false)?;
        if r.ok {
            break;
        }
        let code = serde_json::from_str::<Value>(&r.stderr)
            .ok()
            .and_then(|v| v["error"]["code"].as_str().map(String::from));
        if code.as_deref() != Some("agent_pane_busy") || Instant::now() >= deadline {
            eprintln!("{}", r.stderr);
            return Err(format!("could not start pi in pane {pane}"));
        }
        if !announced {
            info(&format!("Waiting for shell initialization in pane {pane} (e.g. direnv)."));
            announced = true;
        }
        thread::sleep(Duration::from_millis(500));
    }
    if o.focus {
        ok("herdr", &["agent", "focus", &name], false)?;
    }
    if !prompt.is_empty() {
        // Herdr can report Pi ready while its project-trust selector is still open.
        // Pi sets this title after its interactive UI and startup extensions initialize.
        let deadline = Instant::now() + Duration::from_secs(300);
        let mut announced = false;
        loop {
            let r = run("herdr", &["agent", "get", &name], false)?;
            if !r.ok {
                return Err(format!("cannot inspect {name}; prompt was not sent"));
            }
            let v: Value = serde_json::from_str(&r.stdout).unwrap_or(Value::Null);
            let agent = &v["result"]["agent"];
            if agent["terminal_title_stripped"].as_str().unwrap_or("").starts_with("π - ") {
                if agent["agent_status"].as_str() == Some("blocked") {
                    return Err(format!("{name} is blocked; prompt was not sent"));
                }
                break;
            }
            if !announced {
                info(&format!("Waiting for Pi startup in {name}; resolve any project-trust dialog there."));
                announced = true;
            }
            if Instant::now() >= deadline {
                return Err(format!("timed out waiting for {name}; prompt was not sent"));
            }
            thread::sleep(Duration::from_millis(250));
        }
        // Confirm the turn starts, but do not wait for the task to finish or retry a
        // stalled submission: Herdr cannot prove that a timed-out prompt was lost.
        let r = run(
            "herdr",
            &["agent", "prompt", &name, &prompt, "--wait", "--until", "working", "--timeout", "15000"],
            false,
        )?;
        if !r.ok {
            return Err(format!(
                "could not confirm prompt delivery to {name}; it may already have been sent, so inspect the pane before retrying"
            ));
        }
    }
    println!("Started {name} in {checkout} (workspace {workspace}, pane {pane})");
    Ok(())
}

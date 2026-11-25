mod args;
mod pi;
mod start;
mod tui;

use args::{Options, Res};
use clap::Parser;
use std::io::IsTerminal;
use std::process::{exit, Command};

fn run(argv: Vec<String>) -> Res<()> {
    let argv = std::iter::once("wt start".to_string()).chain(argv);
    match Options::try_parse_from(argv) {
        Ok(options) => start::start(options),
        Err(e) => e.exit(),
    }
}

/// Pane that was focused when herdr opened this popup, if run from one.
///
/// Popups get `HERDR_ACTIVE_PANE_ID` but not `HERDR_PANE_ID`, and start in herdr's
/// own directory rather than the pane's.
fn popup_pane() -> Option<String> {
    if std::env::var_os("HERDR_PANE_ID").is_some() {
        return None;
    }
    std::env::var("HERDR_ACTIVE_PANE_ID").ok().filter(|p| !p.is_empty())
}

/// Moves to the working directory of the pane the popup was opened from.
fn enter_pane_directory(pane: &str) {
    let Ok(out) = Command::new("herdr").args(["pane", "get", pane]).output() else { return };
    let Ok(json) = serde_json::from_slice::<serde_json::Value>(&out.stdout) else { return };
    let pane = &json["result"]["pane"];
    if let Some(dir) = pane["foreground_cwd"].as_str().or_else(|| pane["cwd"].as_str()) {
        let _ = std::env::set_current_dir(dir);
    }
}

fn main() {
    let popup = popup_pane();
    if let Some(pane) = &popup {
        enter_pane_directory(pane);
    }
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let result = if !argv.is_empty() || !std::io::stdin().is_terminal() || !std::io::stdout().is_terminal() {
        run(argv)
    } else {
        match tui::prompt_line() {
            Ok(Some(options)) => start::start(options),
            Ok(None) => Ok(()),
            Err(e) => Err(e.to_string()),
        }
    };
    if let Err(e) = result {
        eprintln!("wt start: {e}");
        if popup.is_some() {
            // The popup closes with this process: keep the error readable.
            eprint!("\nPress enter to close.");
            let _ = std::io::stdin().read_line(&mut String::new());
        }
        exit(1);
    }
}

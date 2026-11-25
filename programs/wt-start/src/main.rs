mod args;
mod pi;
mod start;
mod tui;

use args::{Options, Res};
use clap::Parser;
use std::io::IsTerminal;
use std::process::exit;

fn run(argv: Vec<String>) -> Res<()> {
    let argv = std::iter::once("wt start".to_string()).chain(argv);
    match Options::try_parse_from(argv) {
        Ok(options) => start::start(options),
        Err(e) => e.exit(),
    }
}

fn main() {
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
        exit(1);
    }
}

use clap::Parser;
use std::path::PathBuf;

pub type Res<T> = Result<T, String>;

pub const EFFORTS: [&str; 7] = ["off", "minimal", "low", "medium", "high", "xhigh", "max"];

/// Start a pi agent in a new worktree and herdr pane.
///
/// Without arguments, prompts for them interactively.
#[derive(Parser)]
#[command(name = "wt start", bin_name = "wt start", version)]
#[command(group(clap::ArgGroup::new("target").required(true).args(["branch", "pr"])))]
pub struct Options {
    /// Branch to start; created when it does not exist
    #[arg(value_parser = non_empty)]
    pub branch: Option<String>,

    /// Base to create the branch from (worktrunk shortcuts such as pr:123 work)
    #[arg(long, conflicts_with = "pr", value_parser = non_empty)]
    pub base: Option<String>,

    /// Start from a pull request's head branch
    #[arg(long, value_name = "NUMBER")]
    pub pr: Option<u64>,

    /// Ask the agent to fix the pull request's failed checks (requires --pr)
    #[arg(long, requires = "pr", conflicts_with = "prompt_file")]
    pub fix: bool,

    /// Model for the agent
    #[arg(short, long, value_parser = non_empty)]
    pub model: Option<String>,

    /// Thinking effort for the agent
    #[arg(short, long, value_parser = clap::builder::PossibleValuesParser::new(EFFORTS))]
    pub effort: Option<String>,

    /// Prompt to send once the agent is ready
    #[arg(short, long, conflicts_with = "prompt_file", value_parser = non_empty, allow_hyphen_values = true)]
    pub prompt: Option<String>,

    /// File containing the prompt
    #[arg(long, value_name = "FILE")]
    pub prompt_file: Option<PathBuf>,

    /// Run as if started in this directory
    #[arg(short, long, value_name = "DIR")]
    pub working_dir: Option<PathBuf>,

    /// Focus the new agent
    #[arg(long)]
    pub focus: bool,

    /// Generate the branch name from the prompt (set by the interactive form)
    #[arg(skip)]
    pub auto_branch: bool,
}

/// Branch names cannot contain whitespace: runs of it become a single `-`.
pub fn normalize_branch(name: &str) -> String {
    name.split_whitespace().collect::<Vec<_>>().join("-")
}

fn non_empty(s: &str) -> Result<String, String> {
    if s.is_empty() {
        Err("must not be empty".into())
    } else {
        Ok(s.to_string())
    }
}

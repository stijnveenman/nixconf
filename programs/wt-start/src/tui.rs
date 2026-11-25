use crate::args::{Options, EFFORTS};
use ratatui::backend::CrosstermBackend;
use ratatui::crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, KeyboardEnhancementFlags,
    PopKeyboardEnhancementFlags, PushKeyboardEnhancementFlags,
};
use ratatui::crossterm::cursor::MoveTo;
use ratatui::crossterm::execute;
use ratatui::crossterm::terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType};
use ratatui::layout::{Constraint, Layout, Position, Rect};
use ratatui::style::{Color, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph};
use ratatui::{Frame, Terminal, TerminalOptions, Viewport};
use std::sync::mpsc::{self, Receiver};
use std::time::Duration;
use std::{env, fs, io, path::PathBuf, process::Command, thread};
use unicode_width::UnicodeWidthChar;

// Catppuccin Mocha.
const SURFACE2: Color = Color::Rgb(0x58, 0x5b, 0x70);
const OVERLAY1: Color = Color::Rgb(0x7f, 0x84, 0x9c);
const SUBTEXT0: Color = Color::Rgb(0xa6, 0xad, 0xc8);
const TEXT: Color = Color::Rgb(0xcd, 0xd6, 0xf4);
const MAUVE: Color = Color::Rgb(0xcb, 0xa6, 0xf7);
const RED: Color = Color::Rgb(0xf3, 0x8b, 0xa8);

const MAX_PROMPT_ROWS: usize = 8;
const MAX_PICK_ROWS: usize = 7;

// ---------------------------------------------------------------- text buffer

/// Editable text with a cursor; single-line or multi-line with soft wrapping.
#[derive(Default)]
struct TextBuf {
    chars: Vec<char>,
    cursor: usize,
    multiline: bool,
}

fn cw(c: char) -> usize {
    c.width().unwrap_or(0)
}

fn width_of(chars: &[char]) -> usize {
    chars.iter().map(|&c| cw(c)).sum()
}

impl TextBuf {
    fn new(text: &str) -> Self {
        let chars: Vec<char> = text.chars().collect();
        TextBuf { cursor: chars.len(), chars, multiline: false }
    }

    fn text(&self) -> String {
        self.chars.iter().collect()
    }

    /// Visual rows as `[start, end)` char ranges, wrapped at `width` columns.
    fn rows(&self, width: usize) -> Vec<(usize, usize)> {
        let width = width.max(1);
        let mut rows = Vec::new();
        let mut start = 0;
        let mut acc = 0;
        for (i, &c) in self.chars.iter().enumerate() {
            if c == '\n' {
                rows.push((start, i));
                start = i + 1;
                acc = 0;
            } else if acc + cw(c) > width && i > start {
                rows.push((start, i));
                start = i;
                acc = cw(c);
            } else {
                acc += cw(c);
            }
        }
        rows.push((start, self.chars.len()));
        // The cursor after a completely full last row needs a row of its own.
        let (s, e) = *rows.last().unwrap();
        if e == self.chars.len() && width_of(&self.chars[s..e]) >= width {
            rows.push((e, e));
        }
        rows
    }

    /// (row, column) of the cursor within `rows`.
    fn cursor_pos(&self, rows: &[(usize, usize)]) -> (usize, usize) {
        let row = rows.iter().rposition(|&(s, _)| s <= self.cursor).unwrap_or(0);
        (row, width_of(&self.chars[rows[row].0..self.cursor]))
    }

    fn move_vertical(&mut self, width: usize, delta: isize) {
        let rows = self.rows(width);
        let (row, col) = self.cursor_pos(&rows);
        let Some(target) = row.checked_add_signed(delta).filter(|&r| r < rows.len()) else {
            return;
        };
        let (s, e) = rows[target];
        let mut acc = 0;
        let mut idx = s;
        while idx < e && acc + cw(self.chars[idx]) <= col {
            acc += cw(self.chars[idx]);
            idx += 1;
        }
        self.cursor = idx;
    }

    fn line_start(&self) -> usize {
        self.chars[..self.cursor].iter().rposition(|&c| c == '\n').map_or(0, |i| i + 1)
    }

    fn line_end(&self) -> usize {
        self.chars[self.cursor..]
            .iter()
            .position(|&c| c == '\n')
            .map_or(self.chars.len(), |i| self.cursor + i)
    }

    fn word_start(&self) -> usize {
        let mut i = self.cursor;
        while i > 0 && self.chars[i - 1].is_whitespace() {
            i -= 1;
        }
        while i > 0 && !self.chars[i - 1].is_whitespace() {
            i -= 1;
        }
        i
    }

    fn word_end(&self) -> usize {
        let mut i = self.cursor;
        while i < self.chars.len() && self.chars[i].is_whitespace() {
            i += 1;
        }
        while i < self.chars.len() && !self.chars[i].is_whitespace() {
            i += 1;
        }
        i
    }

    fn delete(&mut self, from: usize, to: usize) {
        self.chars.drain(from..to);
        self.cursor = from;
    }

    fn insert(&mut self, c: char) {
        self.chars.insert(self.cursor, c);
        self.cursor += 1;
    }

    /// Applies an editing key; returns whether the key was an editing key.
    fn handle_key(&mut self, key: &KeyEvent, width: usize) -> bool {
        let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
        let alt = key.modifiers.contains(KeyModifiers::ALT);
        let shift = key.modifiers.contains(KeyModifiers::SHIFT);
        let len = self.chars.len();
        match key.code {
            KeyCode::Enter if self.multiline && shift => self.insert('\n'),
            KeyCode::Char('a') if ctrl => self.cursor = self.line_start(),
            KeyCode::Home => self.cursor = self.line_start(),
            KeyCode::End => self.cursor = self.line_end(),
            KeyCode::Char('u') if ctrl => self.delete(self.line_start(), self.cursor),
            KeyCode::Char('k') if ctrl => self.delete(self.cursor, self.line_end()),
            KeyCode::Char('w') if ctrl => self.delete(self.word_start(), self.cursor),
            KeyCode::Backspace if alt => self.delete(self.word_start(), self.cursor),
            KeyCode::Char('d') if alt => self.delete(self.cursor, self.word_end()),
            KeyCode::Char('b') if alt => self.cursor = self.word_start(),
            KeyCode::Char('f') if alt => self.cursor = self.word_end(),
            KeyCode::Left if ctrl || alt => self.cursor = self.word_start(),
            KeyCode::Right if ctrl || alt => self.cursor = self.word_end(),
            KeyCode::Left => self.cursor = self.cursor.saturating_sub(1),
            KeyCode::Right => self.cursor = (self.cursor + 1).min(len),
            KeyCode::Up if self.multiline => self.move_vertical(width, -1),
            KeyCode::Down if self.multiline => self.move_vertical(width, 1),
            KeyCode::Backspace if self.cursor > 0 => self.delete(self.cursor - 1, self.cursor),
            KeyCode::Delete if self.cursor < len => self.delete(self.cursor, self.cursor + 1),
            KeyCode::Char(c) if !ctrl && !alt => self.insert(c),
            _ => return false,
        }
        true
    }
}

// ------------------------------------------------------------------- settings

fn pi_settings() -> serde_json::Value {
    let dir = env::var_os("PI_CODING_AGENT_DIR")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|h| PathBuf::from(h).join(".pi/agent")));
    dir.and_then(|d| fs::read_to_string(d.join("settings.json")).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(serde_json::Value::Null)
}

fn default_model(settings: &serde_json::Value) -> String {
    match (settings["defaultProvider"].as_str(), settings["defaultModel"].as_str()) {
        (Some(p), Some(m)) if !p.is_empty() && !m.is_empty() => format!("{p}/{m}"),
        (_, Some(m)) if !m.is_empty() => m.to_string(),
        _ => "default".into(),
    }
}

fn default_effort(settings: &serde_json::Value, model: &str) -> String {
    settings["modelThinkingLevels"][model]
        .as_str()
        .or_else(|| settings["defaultThinkingLevel"].as_str())
        .filter(|e| EFFORTS.contains(e))
        .unwrap_or("medium")
        .to_string()
}

fn glob(p: &[u8], s: &[u8]) -> bool {
    match p.split_first() {
        None => s.is_empty(),
        Some((b'*', rest)) => (0..=s.len()).any(|i| glob(rest, &s[i..])),
        Some((c, rest)) => s.first() == Some(c) && glob(rest, &s[1..]),
    }
}

/// A scoped model: `provider/id`, with the thinking level a pattern pins, if any.
type Scoped = (String, Option<String>);

fn split_level(pattern: &str) -> (&str, Option<String>) {
    match pattern.rsplit_once(':') {
        Some((m, l)) if EFFORTS.contains(&l) => (m, Some(l.to_string())),
        _ => (pattern, None),
    }
}

fn is_exact(pattern: &str) -> bool {
    let (m, _) = split_level(pattern);
    m.contains('/') && !m.contains('*')
}

/// Resolves pi's `enabledModels` patterns against `pi --list-models`.
fn resolve_models(patterns: &[String]) -> Vec<Scoped> {
    let all: Vec<String> = Command::new("pi")
        .arg("--list-models")
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .skip(1)
                .filter_map(|l| {
                    let mut it = l.split_whitespace();
                    Some(format!("{}/{}", it.next()?, it.next()?))
                })
                .collect()
        })
        .unwrap_or_default();
    let mut out: Vec<Scoped> = Vec::new();
    let mut push = |m: String, l: Option<String>| {
        if !out.iter().any(|(x, _)| *x == m) {
            out.push((m, l));
        }
    };
    if patterns.is_empty() {
        all.into_iter().for_each(|m| push(m, None));
        return out;
    }
    for pattern in patterns {
        let (p, level) = split_level(pattern);
        let lower = p.to_lowercase();
        for m in &all {
            let id = m.split_once('/').map_or(m.as_str(), |(_, id)| id);
            if glob(lower.as_bytes(), m.to_lowercase().as_bytes())
                || glob(lower.as_bytes(), id.to_lowercase().as_bytes())
                || (!lower.contains('*') && m.to_lowercase().contains(&lower))
            {
                push(m.clone(), level.clone());
            }
        }
        if is_exact(pattern) {
            push(p.to_string(), level.clone());
        }
    }
    out
}

/// Scoped models, resolved in the background when patterns need expanding.
struct Models {
    list: Vec<Scoped>,
    pending: Option<Receiver<Vec<Scoped>>>,
}

impl Models {
    fn new(settings: &serde_json::Value) -> Self {
        let patterns: Vec<String> = settings["enabledModels"]
            .as_array()
            .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
            .unwrap_or_default();
        if !patterns.is_empty() && patterns.iter().all(|p| is_exact(p)) {
            let list = patterns.iter().map(|p| {
                let (m, l) = split_level(p);
                (m.to_string(), l)
            });
            return Models { list: list.collect(), pending: None };
        }
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            let _ = tx.send(resolve_models(&patterns));
        });
        Models { list: Vec::new(), pending: Some(rx) }
    }

    fn poll(&mut self) {
        if let Some(rx) = &self.pending {
            if let Ok(list) = rx.try_recv() {
                self.list = list;
                self.pending = None;
            }
        }
    }
}

// ------------------------------------------------------------------------ app

#[derive(Clone, Copy, PartialEq)]
enum Field {
    Base,
    Branch,
    Dir,
}

#[derive(Clone, Copy, PartialEq)]
enum Pick {
    Model,
    Effort,
}

enum Panel {
    None,
    Edit { field: Field, buf: TextBuf, error: Option<String> },
    Pick { kind: Pick, filter: TextBuf, sel: usize },
}

struct App {
    prompt: TextBuf,
    prompt_scroll: usize,
    model: String,
    effort: String,
    base: String,
    /// Worktrunk's default branch, used (by omitting --base) unless `base` differs.
    base_default: String,
    branch: String,
    dir: String,
    focus: bool,
    panel: Panel,
    models: Models,
}

fn worktrunk_default_branch() -> Option<String> {
    let out = Command::new("wt").args(["config", "state", "default-branch", "get"]).output().ok()?;
    let branch = String::from_utf8_lossy(&out.stdout).trim().to_string();
    (out.status.success() && !branch.is_empty()).then_some(branch)
}

fn tilde(path: &str) -> String {
    match env::var("HOME") {
        Ok(home) if path == home => "~".into(),
        Ok(home) if path.starts_with(&format!("{home}/")) => format!("~{}", &path[home.len()..]),
        _ => path.to_string(),
    }
}

fn untilde(path: &str) -> PathBuf {
    match (path.strip_prefix('~'), env::var("HOME")) {
        (Some(rest), Ok(home)) if rest.is_empty() || rest.starts_with('/') => PathBuf::from(format!("{home}{rest}")),
        _ => PathBuf::from(path),
    }
}

impl App {
    /// Picker entries as (value, label).
    fn items(&self, kind: Pick, filter: &str) -> Vec<(String, String)> {
        match kind {
            Pick::Effort => EFFORTS.iter().map(|e| (e.to_string(), e.to_string())).collect(),
            Pick::Model => {
                let f = filter.to_lowercase();
                self.models
                    .list
                    .iter()
                    .filter(|(m, _)| m.to_lowercase().contains(&f))
                    .map(|(m, l)| (m.clone(), l.as_ref().map_or(m.clone(), |l| format!("{m} ({l})"))))
                    .collect()
            }
        }
    }

    fn panel_height(&self) -> usize {
        match &self.panel {
            Panel::None => 0,
            Panel::Edit { .. } => 1,
            Panel::Pick { kind, filter, .. } => 1 + self.items(*kind, &filter.text()).len().clamp(1, MAX_PICK_ROWS),
        }
    }

    fn height(&self, width: usize) -> usize {
        self.prompt.rows(width).len().clamp(1, MAX_PROMPT_ROWS) + 2 + self.panel_height() + 2
    }

    fn open_edit(&mut self, field: Field) {
        let value = match field {
            Field::Base => &self.base,
            Field::Branch => &self.branch,
            Field::Dir => &self.dir,
        };
        self.panel = Panel::Edit { field, buf: TextBuf::new(value), error: None };
    }

    fn open_pick(&mut self, kind: Pick) {
        let current = if kind == Pick::Model { &self.model } else { &self.effort };
        let sel = self.items(kind, "").iter().position(|(v, _)| v == current).unwrap_or(0);
        self.panel = Panel::Pick { kind, filter: TextBuf::default(), sel };
    }

    /// Handles a key; `Some(true)` submits, `Some(false)` cancels.
    fn on_key(&mut self, key: KeyEvent, width: usize) -> Option<bool> {
        let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
        if ctrl && key.code == KeyCode::Char('c') {
            return Some(false);
        }
        match std::mem::replace(&mut self.panel, Panel::None) {
            Panel::None => self.on_prompt_key(key, width),
            Panel::Edit { field, mut buf, mut error } => {
                match key.code {
                    KeyCode::Esc => return None,
                    KeyCode::Enter => {
                        let mut value = buf.text().trim().to_string();
                        match field {
                            Field::Branch if value.is_empty() => error = Some("branch must not be empty".into()),
                            Field::Dir if !untilde(&value).is_dir() => error = Some("not a directory".into()),
                            _ => {
                                match field {
                                    Field::Base if value.is_empty() => self.base = self.base_default.clone(),
                                    Field::Base => self.base = value,
                                    Field::Branch => self.branch = value,
                                    Field::Dir => {
                                        value = tilde(&untilde(&value).to_string_lossy());
                                        self.dir = value;
                                    }
                                }
                                return None;
                            }
                        }
                    }
                    _ => {
                        if buf.handle_key(&key, usize::MAX) {
                            error = None;
                        }
                    }
                }
                self.panel = Panel::Edit { field, buf, error };
                None
            }
            Panel::Pick { kind, mut filter, mut sel } => {
                let items = self.items(kind, &filter.text());
                let last = items.len().saturating_sub(1);
                match key.code {
                    KeyCode::Esc => return None,
                    KeyCode::Enter => {
                        if let Some((value, _)) = items.get(sel) {
                            match kind {
                                Pick::Effort => self.effort = value.clone(),
                                Pick::Model => {
                                    // A scoped model may pin its thinking level.
                                    if let Some((_, Some(level))) = self.models.list.iter().find(|(m, _)| m == value) {
                                        self.effort = level.clone();
                                    }
                                    self.model = value.clone();
                                }
                            }
                            return None;
                        }
                    }
                    KeyCode::Up => sel = sel.saturating_sub(1),
                    KeyCode::Down => sel = (sel + 1).min(last),
                    KeyCode::Char('p') if ctrl => sel = sel.saturating_sub(1),
                    KeyCode::Char('n') if ctrl => sel = (sel + 1).min(last),
                    _ => {
                        if kind == Pick::Model && filter.handle_key(&key, usize::MAX) {
                            sel = 0;
                        }
                    }
                }
                self.panel = Panel::Pick { kind, filter, sel };
                None
            }
        }
    }

    fn on_prompt_key(&mut self, key: KeyEvent, width: usize) -> Option<bool> {
        let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
        let alt = key.modifiers.contains(KeyModifiers::ALT);
        let plain_enter = key.code == KeyCode::Enter && !key.modifiers.contains(KeyModifiers::SHIFT);
        match key.code {
            KeyCode::Esc => return Some(false),
            KeyCode::Enter if plain_enter => return Some(true),
            // Ctrl+M needs the kitty keyboard protocol (it is Enter otherwise); Alt+M works anywhere.
            KeyCode::Char('m') if ctrl || alt => self.open_pick(Pick::Model),
            KeyCode::Char('e') if ctrl => self.open_pick(Pick::Effort),
            KeyCode::Char('r') if ctrl => self.open_edit(Field::Base),
            KeyCode::Char('b') if ctrl => self.open_edit(Field::Branch),
            KeyCode::Char('d') if ctrl => self.open_edit(Field::Dir),
            KeyCode::Char('f') if ctrl => self.focus = !self.focus,
            _ => {
                self.prompt.handle_key(&key, width);
            }
        }
        None
    }

    fn options(&self) -> Options {
        let some = |s: &str| (!s.trim().is_empty()).then(|| s.trim().to_string());
        Options {
            branch: some(&self.branch),
            base: (self.base != self.base_default).then(|| self.base.clone()),
            pr: None,
            fix: false,
            model: (self.model != "default").then(|| self.model.clone()),
            effort: Some(self.effort.clone()),
            prompt: some(&self.prompt.text()),
            prompt_file: None,
            working_dir: Some(untilde(&self.dir)),
            focus: self.focus,
        }
    }
}

// ------------------------------------------------------------------- drawing

fn dim(s: impl Into<String>) -> Span<'static> {
    Span::styled(s.into(), Style::new().fg(OVERLAY1))
}

fn val(s: impl Into<String>) -> Span<'static> {
    Span::styled(s.into(), Style::new().fg(SUBTEXT0))
}

fn accent(s: impl Into<String>) -> Span<'static> {
    Span::styled(s.into(), Style::new().fg(MAUVE))
}

fn draw(f: &mut Frame, app: &App) {
    let area = f.area();
    let prompt_rows = app.prompt.rows(area.width as usize);
    let visible = prompt_rows.len().clamp(1, MAX_PROMPT_ROWS) as u16;
    let [box_area, panel_area, status_area, hints_area] = Layout::vertical([
        Constraint::Length(visible + 2),
        Constraint::Length(app.panel_height() as u16),
        Constraint::Length(1),
        Constraint::Length(1),
    ])
    .areas(area);

    // Like pi: only a top and bottom rule around the prompt.
    let block = Block::default().borders(Borders::TOP | Borders::BOTTOM).border_style(Style::new().fg(SURFACE2));
    let inner = block.inner(box_area);
    f.render_widget(block, box_area);

    let mut cursor = None;
    if app.prompt.chars.is_empty() {
        f.render_widget(Paragraph::new(dim(" > prompt")), inner);
    } else {
        let lines: Vec<Line> = prompt_rows[app.prompt_scroll..]
            .iter()
            .take(visible as usize)
            .map(|&(s, e)| Line::from(Span::styled(app.prompt.chars[s..e].iter().collect::<String>(), Style::new().fg(TEXT))))
            .collect();
        f.render_widget(Paragraph::new(lines), inner);
    }
    if matches!(app.panel, Panel::None) {
        let (row, col) = app.prompt.cursor_pos(&prompt_rows);
        cursor = Some(Position::new(inner.x + col as u16, inner.y + (row - app.prompt_scroll) as u16));
    }

    draw_panel(f, app, panel_area, &mut cursor);

    // Settings line; the one being edited is highlighted.
    let (editing, picking) = match &app.panel {
        Panel::Edit { field, .. } => (Some(*field), None),
        Panel::Pick { kind, .. } => (None, Some(*kind)),
        Panel::None => (None, None),
    };
    let label = |text: &str, on: bool| if on { accent(text) } else { dim(text) };
    let sep = || dim(" · ");
    // Give the directory whatever width the other settings leave, trimming its start.
    let others = 1 + app.effort.chars().count()
        + " · base: ".chars().count() + app.base.chars().count()
        + " · branch: ".chars().count() + app.branch.chars().count()
        + " · dir: ".chars().count()
        + " · focus: ".chars().count() + app.focus.to_string().chars().count();
    // Drop the provider prefix when the line would not fit otherwise.
    let model = if 1 + app.model.chars().count() + others + 16 > area.width as usize {
        app.model.rsplit('/').next().unwrap_or(&app.model).to_string()
    } else {
        app.model.clone()
    };
    let fixed = 1 + model.chars().count() + others;
    let room = (area.width as usize).saturating_sub(fixed).max(8);
    let dir = if app.dir.chars().count() > room {
        let tail: String = app.dir.chars().skip(app.dir.chars().count() - (room - 1)).collect();
        format!("…{tail}")
    } else {
        app.dir.clone()
    };
    let status = Line::from(vec![
        Span::raw(" "),
        if picking == Some(Pick::Model) { accent(model) } else { val(model) },
        label(":", picking == Some(Pick::Effort)),
        if picking == Some(Pick::Effort) { accent(app.effort.clone()) } else { val(app.effort.clone()) },
        sep(),
        label("base: ", editing == Some(Field::Base)),
        val(app.base.clone()),
        sep(),
        label("branch: ", editing == Some(Field::Branch)),
        val(app.branch.clone()),
        sep(),
        label("dir: ", editing == Some(Field::Dir)),
        val(dir),
        sep(),
        dim("focus: "),
        val(app.focus.to_string()),
    ]);
    f.render_widget(Paragraph::new(status), status_area);
    let hints = " ^M model  ^E effort  ^R base  ^B branch  ^D dir  ^F focus  shift+enter newline";
    f.render_widget(Paragraph::new(dim(hints)), hints_area);

    if let Some(pos) = cursor {
        f.set_cursor_position(pos);
    }
}

/// Renders `label › text` on one row, scrolling only the text; returns the cursor position.
fn draw_field(f: &mut Frame, row: Rect, name: &str, buf: &TextBuf, suffix: Option<Span<'static>>) -> Position {
    let prefix = format!(" {name} › ");
    let [label_area, text_area] =
        Layout::horizontal([Constraint::Length(prefix.chars().count() as u16), Constraint::Min(1)]).areas(row);
    f.render_widget(Paragraph::new(accent(prefix)), label_area);
    let col = width_of(&buf.chars[..buf.cursor]);
    let scroll = (col + 1).saturating_sub(text_area.width as usize);
    let mut spans = vec![Span::styled(buf.text(), Style::new().fg(TEXT))];
    spans.extend(suffix);
    f.render_widget(Paragraph::new(Line::from(spans)).scroll((0, scroll as u16)), text_area);
    Position::new(text_area.x + (col - scroll) as u16, row.y)
}

fn draw_panel(f: &mut Frame, app: &App, area: Rect, cursor: &mut Option<Position>) {
    if area.height == 0 {
        return;
    }
    let header = Rect { height: 1, ..area };
    match &app.panel {
        Panel::None => {}
        Panel::Edit { field, buf, error } => {
            let name = match field {
                Field::Base => "base",
                Field::Branch => "branch",
                Field::Dir => "dir",
            };
            let suffix = match error {
                Some(e) => Span::styled(format!("  {e}"), Style::new().fg(RED)),
                None => dim("  enter confirm · esc cancel"),
            };
            *cursor = Some(draw_field(f, header, name, buf, Some(suffix)));
        }
        Panel::Pick { kind, filter, sel } => {
            let items = app.items(*kind, &filter.text());
            if *kind == Pick::Model {
                let hint = filter.chars.is_empty().then(|| dim("↑↓ select · enter confirm · esc cancel"));
                *cursor = Some(draw_field(f, header, "model", filter, hint));
            } else {
                let line = Line::from(vec![accent(" effort › "), dim("↑↓ select · enter confirm · esc cancel")]);
                f.render_widget(Paragraph::new(line), header);
            }
            let rows = (area.height as usize).saturating_sub(1);
            let offset = (*sel + 1).saturating_sub(rows);
            let mut lines: Vec<Line> = items
                .iter()
                .enumerate()
                .skip(offset)
                .take(rows)
                .map(|(i, (value, label))| {
                    let current = value == if *kind == Pick::Model { &app.model } else { &app.effort };
                    let text = format!("{label}{}", if current { " ✓" } else { "" });
                    if i == *sel {
                        Line::from(accent(format!(" › {text}")))
                    } else {
                        Line::from(val(format!("   {text}")))
                    }
                })
                .collect();
            if items.is_empty() {
                lines.push(Line::from(dim(if app.models.pending.is_some() { "   loading models…" } else { "   no matches" })));
            }
            f.render_widget(Paragraph::new(lines), Rect { y: area.y + 1, height: area.height - 1, ..area });
        }
    }
}

// ------------------------------------------------------------------- driver

type Term = Terminal<CrosstermBackend<io::Stdout>>;

/// Erases the inline viewport and leaves the cursor at its top-left corner.
fn erase(terminal: &mut Term) -> io::Result<()> {
    let top = terminal.get_frame().area().y;
    execute!(io::stdout(), MoveTo(0, top), Clear(ClearType::FromCursorDown))
}

fn inline_terminal(height: usize) -> io::Result<Term> {
    Terminal::with_options(
        CrosstermBackend::new(io::stdout()),
        TerminalOptions { viewport: Viewport::Inline(height as u16) },
    )
}

/// Renders the interactive form; returns the chosen options, or None on cancel.
pub fn prompt_line() -> io::Result<Option<Options>> {
    let settings = pi_settings();
    let model = default_model(&settings);
    let effort = default_effort(&settings, &model);
    let dir = env::current_dir().map(|d| tilde(&d.to_string_lossy())).unwrap_or_else(|_| ".".into());
    let base_default = worktrunk_default_branch().unwrap_or_else(|| "default".into());
    let mut app = App {
        prompt: TextBuf { multiline: true, ..TextBuf::default() },
        prompt_scroll: 0,
        model,
        effort,
        base: base_default.clone(),
        base_default,
        branch: "auto".into(),
        dir,
        focus: false,
        panel: Panel::None,
        models: Models::new(&settings),
    };

    let mut height = app.height(ratatui::crossterm::terminal::size()?.0 as usize);
    enable_raw_mode()?;
    let mut terminal = inline_terminal(height)?;
    // Reports Ctrl+M and Shift+Enter distinctly from Enter; ignored where unsupported.
    let _ = execute!(io::stdout(), PushKeyboardEnhancementFlags(KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES));

    let result = (|| -> io::Result<Option<Options>> {
        loop {
            let width = terminal.size()?.width as usize;
            app.models.poll();
            // Keep the cursor row inside the visible part of the prompt.
            let rows = app.prompt.rows(width);
            let (cursor_row, _) = app.prompt.cursor_pos(&rows);
            let visible = rows.len().clamp(1, MAX_PROMPT_ROWS);
            app.prompt_scroll = app.prompt_scroll.min(rows.len() - visible);
            if cursor_row < app.prompt_scroll {
                app.prompt_scroll = cursor_row;
            } else if cursor_row >= app.prompt_scroll + visible {
                app.prompt_scroll = cursor_row + 1 - visible;
            }

            let wanted = app.height(width);
            if wanted != height {
                // An inline viewport has a fixed height: recreate it in place.
                erase(&mut terminal)?;
                height = wanted;
                terminal = inline_terminal(height)?;
            }
            terminal.draw(|f| draw(f, &app))?;

            if app.models.pending.is_some() && !event::poll(Duration::from_millis(100))? {
                continue;
            }
            let Event::Key(key) = event::read()? else { continue };
            if key.kind == KeyEventKind::Release {
                continue;
            }
            match app.on_key(key, width) {
                Some(true) => return Ok(Some(app.options())),
                Some(false) => return Ok(None),
                None => {}
            }
        }
    })();
    // Leave the screen clean: erase the form before handing the terminal back.
    let _ = erase(&mut terminal);
    let _ = execute!(io::stdout(), PopKeyboardEnhancementFlags);
    // Not ratatui::restore: it would also leave an alternate screen we never entered.
    let _ = disable_raw_mode();
    result
}

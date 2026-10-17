//! Desktop theming for Screen AI.
//!
//! Colors and a few shape/type/motion knobs come from one human-editable file,
//! `~/.config/screen-ai/theme.conf`. Its `[palette]` section decides which
//! sources win, in this order (first match wins, missing roles fall through):
//!
//!   1. explicit colors written in theme.conf
//!   2. `colors.conf` written by Matugen (see `theming/matugen/`)
//!   3. the active Qt / KDE color scheme (kdeglobals, qt5ct, qt6ct)
//!   4. GTK colors (`@define-color` in gtk-4.0 / gtk-3.0 `gtk.css`)
//!   5. Screen AI's built-in dark/light colors
//!
//! Nothing here needs a restart: `spawn_watcher` polls the relevant files and
//! emits `theme-changed` whenever one of them changes, even while the overlay
//! is hidden, so a Matugen run in the background is already applied when the
//! overlay is summoned again.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use serde::Serialize;

/// The color roles that can be read from KDE/Qt/GTK/Matugen sources and mapped
/// onto Screen AI's WebView UI. A native Qt widget style itself cannot style HTML.
#[derive(Serialize, Clone, Debug, Default)]
pub struct QtPalette {
    pub name: Option<String>,
    pub dark: Option<bool>,
    pub window: Option<String>,
    pub window_text: Option<String>,
    pub base: Option<String>,
    pub text: Option<String>,
    pub alternate_base: Option<String>,
    pub button: Option<String>,
    pub button_text: Option<String>,
    pub highlight: Option<String>,
    pub highlighted_text: Option<String>,
    pub link: Option<String>,
    pub tooltip_base: Option<String>,
    pub tooltip_text: Option<String>,
}

/// Non-color knobs from theme.conf. `None` means "use the built-in default".
#[derive(Serialize, Clone, Debug)]
pub struct ThemeTokens {
    /// Absolute path of the theme file, so the UI can show where to edit.
    pub config_path: String,
    /// Card corner radius in px. Inner radii are derived from it in CSS.
    pub radius: Option<u32>,
    pub font: Option<String>,
    pub mono: Option<String>,
    pub font_size: Option<f32>,
    /// `[motion] mode = reduced` (or `off`) disables non-essential animation.
    pub motion_reduced: bool,
    /// Multiplier for animation durations; 1.0 is the default, 2.0 is slower.
    pub speed: f32,
}

#[derive(Serialize, Clone, Debug)]
pub struct SystemTheme {
    pub dark: bool,
    /// Accent/selection color as #rrggbb when the desktop exposes one.
    pub accent: Option<String>,
    /// Merged palette from every enabled layer, if any layer had colors.
    pub palette: Option<QtPalette>,
    /// First layer that supplied colors: explicit, matugen, qt, gtk, or builtin.
    pub source: String,
    pub tokens: ThemeTokens,
}

type Ini = HashMap<String, HashMap<String, String>>;

const SOURCES: [&str; 5] = ["auto", "matugen", "qt", "gtk", "builtin"];
const DEFAULT_THEME_CONFIG: &str = include_str!("../../theming/theme.conf");

// ─── Paths ───────────────────────────────────────────────────────────────────

fn config_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(dirs::config_dir)
}

fn config_root() -> PathBuf {
    config_dir().unwrap_or_else(|| PathBuf::from("/tmp"))
}

pub fn screen_ai_config_dir() -> PathBuf {
    config_root().join("screen-ai")
}

pub fn theme_config_path() -> PathBuf {
    screen_ai_config_dir().join("theme.conf")
}

fn default_matugen_path() -> PathBuf {
    screen_ai_config_dir().join("colors.conf")
}

fn expand_path(raw: &str) -> PathBuf {
    let raw = unquote(raw);
    let home = || dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
    if raw == "~" {
        return home();
    }
    if let Some(rest) = raw.strip_prefix("~/") {
        return home().join(rest);
    }
    PathBuf::from(raw)
}

/// Writes the commented default theme.conf on first run. Existing files are
/// never touched, so user edits survive updates.
pub fn ensure_theme_config() {
    let path = theme_config_path();
    if path.exists() {
        return;
    }
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Err(error) = std::fs::write(&path, DEFAULT_THEME_CONFIG) {
        eprintln!("screen-ai: could not create {}: {error}", path.display());
    }
}

// ─── INI parsing ─────────────────────────────────────────────────────────────

/// Keys are lowercased and section names too, so lookups are case-insensitive.
/// Top-level keys (before any `[section]`) live under the empty section name.
fn parse_ini(text: &str) -> Ini {
    let mut ini = Ini::new();
    let mut section = String::new();

    for raw_line in text.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') && line.len() >= 2 {
            section = line[1..line.len() - 1].trim().to_lowercase();
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        ini.entry(section.clone())
            .or_default()
            .insert(key.trim().to_lowercase(), strip_inline_comment(value.trim()).to_string());
    }
    ini
}

/// `window = #141318  # background` → `#141318`. A `#` only starts a comment
/// when it is preceded by whitespace and followed by whitespace or the end of
/// the line, so hex colors such as `#141318` are never cut.
fn strip_inline_comment(value: &str) -> &str {
    let mut previous_is_space = false;
    for (index, ch) in value.char_indices() {
        if ch == '#' && index > 0 && previous_is_space {
            let next_is_space = value[index + 1..]
                .chars()
                .next()
                .map_or(true, |next| next.is_whitespace());
            if next_is_space {
                return value[..index].trim_end();
            }
        }
        previous_is_space = ch.is_whitespace();
    }
    value
}

fn ini_value<'a>(ini: &'a Ini, section: &str, key: &str) -> Option<&'a str> {
    ini.get(&section.to_lowercase())
        .and_then(|items| items.get(&key.to_lowercase()))
        .map(String::as_str)
}

fn unquote(value: &str) -> &str {
    value
        .trim()
        .trim_matches('"')
        .trim_matches('\'')
        .trim()
}

fn read_ini(path: &Path) -> Option<Ini> {
    let text = std::fs::read_to_string(path).ok()?;
    Some(parse_ini(&text))
}

// ─── Color parsing ───────────────────────────────────────────────────────────

/// Converts KDE's `r,g,b` values and Qt/CSS hex colors to CSS-friendly
/// #rrggbb. Alpha is dropped for #RGBA and Qt's #AARRGGBB forms.
fn color_to_hex(value: &str) -> Option<String> {
    let value = unquote(value);
    let value = value.strip_prefix("rgb(").and_then(|v| v.strip_suffix(')')).unwrap_or(value);

    if let Some(hex) = value.strip_prefix('#') {
        let hex = hex.trim();
        let expanded = match hex.len() {
            3 => hex.chars().flat_map(|ch| [ch, ch]).collect::<String>(),
            4 => hex.chars().take(3).flat_map(|ch| [ch, ch]).collect::<String>(), // CSS #RGBA
            6 => hex.to_string(),
            8 => hex[2..].to_string(), // Qt #AARRGGBB
            _ => return None,
        };
        if !expanded.chars().all(|c| c.is_ascii_hexdigit()) {
            return None;
        }
        return Some(format!("#{}", expanded.to_lowercase()));
    }

    let channels: Vec<u8> = value
        .split(',')
        .take(3)
        .map(|part| part.trim().parse::<u8>().ok())
        .collect::<Option<Vec<_>>>()?;
    if channels.len() != 3 {
        return None;
    }
    Some(format!("#{:02x}{:02x}{:02x}", channels[0], channels[1], channels[2]))
}

/// GTK CSS colors are `#rrggbbaa`, the opposite alpha position from Qt's
/// `#aarrggbb`, so they need their own parser.
fn css_color(value: &str) -> Option<String> {
    let value = value.trim();
    if let Some(hex) = value.strip_prefix('#') {
        if hex.len() == 8 {
            return hex.get(..6).and_then(|rgb| color_to_hex(&format!("#{rgb}")));
        }
    }
    color_to_hex(value)
}

fn color_from(ini: &Ini, sections: &[&str], keys: &[&str]) -> Option<String> {
    for section in sections {
        for key in keys {
            if let Some(value) = ini_value(ini, section, key).and_then(color_to_hex) {
                return Some(value);
            }
        }
    }
    None
}

fn set_if_missing(target: &mut Option<String>, value: Option<String>) {
    if target.is_none() {
        *target = value;
    }
}

fn color_list(value: &str) -> Vec<Option<String>> {
    value.split(',').map(color_to_hex).collect()
}

fn color_is_dark(hex: &str) -> Option<bool> {
    let hex = color_to_hex(hex)?;
    let r = u8::from_str_radix(&hex[1..3], 16).ok()? as f32;
    let g = u8::from_str_radix(&hex[3..5], 16).ok()? as f32;
    let b = u8::from_str_radix(&hex[5..7], 16).ok()? as f32;
    Some((0.299 * r + 0.587 * g + 0.114 * b) < 128.0)
}

/// Fill every role that `target` does not have yet from `from`.
fn fill_missing(target: &mut QtPalette, from: &QtPalette) {
    set_if_missing(&mut target.window, from.window.clone());
    set_if_missing(&mut target.window_text, from.window_text.clone());
    set_if_missing(&mut target.base, from.base.clone());
    set_if_missing(&mut target.text, from.text.clone());
    set_if_missing(&mut target.alternate_base, from.alternate_base.clone());
    set_if_missing(&mut target.button, from.button.clone());
    set_if_missing(&mut target.button_text, from.button_text.clone());
    set_if_missing(&mut target.highlight, from.highlight.clone());
    set_if_missing(&mut target.highlighted_text, from.highlighted_text.clone());
    set_if_missing(&mut target.link, from.link.clone());
    set_if_missing(&mut target.tooltip_base, from.tooltip_base.clone());
    set_if_missing(&mut target.tooltip_text, from.tooltip_text.clone());
}

fn palette_has_colors(palette: &QtPalette) -> bool {
    palette.window.is_some()
        || palette.window_text.is_some()
        || palette.base.is_some()
        || palette.text.is_some()
        || palette.alternate_base.is_some()
        || palette.button.is_some()
        || palette.button_text.is_some()
        || palette.highlight.is_some()
        || palette.highlighted_text.is_some()
        || palette.link.is_some()
        || palette.tooltip_base.is_some()
        || palette.tooltip_text.is_some()
}

// ─── theme.conf ──────────────────────────────────────────────────────────────

/// Palette roles use the same key names as `QtPalette`, so a Matugen template
/// or a hand-written `[palette]` section reads the same way.
fn section_palette(ini: &Ini, section: &str) -> QtPalette {
    let get = |key: &str| ini_value(ini, section, key).and_then(color_to_hex);
    QtPalette {
        window: get("window"),
        window_text: get("window_text"),
        base: get("base"),
        text: get("text"),
        alternate_base: get("alternate_base"),
        button: get("button"),
        button_text: get("button_text"),
        highlight: get("highlight"),
        highlighted_text: get("highlighted_text"),
        link: get("link"),
        tooltip_base: get("tooltip_base"),
        tooltip_text: get("tooltip_text"),
        ..QtPalette::default()
    }
}

struct RiceConfig {
    source: String,
    matugen_file: PathBuf,
    explicit: QtPalette,
    radius: Option<u32>,
    font: Option<String>,
    mono: Option<String>,
    font_size: Option<f32>,
    motion_reduced: bool,
    speed: f32,
}

fn read_rice_config() -> RiceConfig {
    let ini = read_ini(&theme_config_path()).unwrap_or_default();
    let text = |section: &str, key: &str| {
        ini_value(&ini, section, key)
            .map(|value| unquote(value).to_string())
            .filter(|value| !value.is_empty())
    };

    let source = text("palette", "source")
        .map(|value| value.to_lowercase())
        .filter(|value| SOURCES.contains(&value.as_str()))
        .unwrap_or_else(|| "auto".to_string());
    let matugen_file = text("palette", "source_file")
        .map(|raw| expand_path(&raw))
        .unwrap_or_else(default_matugen_path);
    let motion_mode = text("motion", "mode").map(|mode| mode.to_lowercase());

    RiceConfig {
        source,
        matugen_file,
        explicit: section_palette(&ini, "palette"),
        radius: text("shape", "radius")
            .and_then(|value| value.parse::<u32>().ok())
            .map(|radius| radius.min(40)),
        font: text("type", "font"),
        mono: text("type", "mono"),
        font_size: text("type", "size")
            .and_then(|value| value.parse::<f32>().ok())
            .filter(|size| size.is_finite() && (8.0..=32.0).contains(size)),
        motion_reduced: matches!(motion_mode.as_deref(), Some("reduced" | "off")),
        speed: text("motion", "speed")
            .and_then(|value| value.parse::<f32>().ok())
            .filter(|speed| speed.is_finite() && *speed > 0.0 && *speed <= 4.0)
            .unwrap_or(1.0),
    }
}

/// Matugen writes `[palette]` (or bare keys). Returns None when it has no colors.
fn read_matugen_palette(path: &Path) -> Option<QtPalette> {
    let ini = read_ini(path)?;
    let mut palette = section_palette(&ini, "palette");
    if !palette_has_colors(&palette) {
        palette = section_palette(&ini, "");
    }
    palette_has_colors(&palette).then_some(palette)
}

// ─── GTK ─────────────────────────────────────────────────────────────────────

/// Collects `@define-color name value;` lines. GTK 4 is read first, so its
/// values win where GTK 3 and GTK 4 both define a name.
fn parse_gtk_defines(path: &Path) -> HashMap<String, String> {
    let mut defines = HashMap::new();
    let Ok(text) = std::fs::read_to_string(path) else {
        return defines;
    };
    for line in text.lines() {
        let Some(rest) = line.trim().strip_prefix("@define-color") else {
            continue;
        };
        let rest = rest.trim().trim_end_matches(';').trim();
        let mut parts = rest.splitn(2, char::is_whitespace);
        let (Some(name), Some(value)) = (parts.next(), parts.next()) else {
            continue;
        };
        let value = value.trim().trim_end_matches(';').trim();
        if !name.is_empty() && !value.is_empty() {
            defines.insert(name.to_lowercase(), value.to_string());
        }
    }
    defines
}

/// Follows `@other_name` references, up to a few hops.
fn resolve_define(value: &str, defines: &HashMap<String, String>) -> Option<String> {
    let mut current = value.trim().to_string();
    for _ in 0..4 {
        match current.strip_prefix('@') {
            Some(name) => current = defines.get(&name.to_lowercase())?.clone(),
            None => return Some(current),
        }
    }
    None
}

fn gtk_palette() -> QtPalette {
    let root = config_root();
    let mut defines: HashMap<String, String> = HashMap::new();
    for dir in ["gtk-4.0", "gtk-3.0"] {
        for (name, value) in parse_gtk_defines(&root.join(dir).join("gtk.css")) {
            defines.entry(name).or_insert(value);
        }
    }
    if defines.is_empty() {
        return QtPalette::default();
    }

    // Names follow libadwaita/GTK 4 first, then GTK 3's theme_* names.
    let pick = |names: &[&str]| {
        names.iter().find_map(|name| {
            let value = defines.get(*name)?;
            let resolved = resolve_define(value, &defines)?;
            css_color(&resolved)
        })
    };
    QtPalette {
        window: pick(&["window_bg_color", "theme_bg_color"]),
        window_text: pick(&["window_fg_color", "theme_fg_color"]),
        base: pick(&["view_bg_color", "theme_base_color"]),
        text: pick(&["view_fg_color", "theme_text_color"]),
        button: pick(&["button_bg_color"]),
        button_text: pick(&["button_fg_color"]),
        highlight: pick(&["accent_bg_color", "theme_selected_bg_color"]),
        highlighted_text: pick(&["accent_fg_color", "theme_selected_fg_color"]),
        link: pick(&["link_color"]),
        ..QtPalette::default()
    }
}

// ─── Qt / KDE ────────────────────────────────────────────────────────────────

/// Apply Qt's documented QPalette::ColorRole ordering from qt5ct/qt6ct's
/// active_colors list. Named colors from a scheme take precedence where present.
fn fill_from_qt_role_list(palette: &mut QtPalette, colors: &[Option<String>]) {
    let role = |index: usize| colors.get(index).cloned().flatten();
    set_if_missing(&mut palette.window_text, role(0));
    set_if_missing(&mut palette.button, role(1));
    set_if_missing(&mut palette.text, role(6));
    set_if_missing(&mut palette.button_text, role(8));
    set_if_missing(&mut palette.base, role(9));
    set_if_missing(&mut palette.window, role(10));
    set_if_missing(&mut palette.highlight, role(12));
    set_if_missing(&mut palette.highlighted_text, role(13));
    set_if_missing(&mut palette.link, role(14));
    set_if_missing(&mut palette.alternate_base, role(16));
    set_if_missing(&mut palette.tooltip_base, role(18));
    set_if_missing(&mut palette.tooltip_text, role(19));
}

fn palette_from_ini(ini: &Ini, name: Option<String>) -> QtPalette {
    let mut palette = QtPalette {
        name: name.or_else(|| {
            ini_value(ini, "general", "colorscheme")
                .or_else(|| ini_value(ini, "appearance", "color_scheme"))
                .map(|s| unquote(s).to_string())
        }),
        ..QtPalette::default()
    };

    // KDE color schemes (kdeglobals and *.colors) group their QPalette roles.
    palette.window = color_from(
        ini,
        &["colors:window", "window", "palette"],
        &["backgroundnormal", "window", "window_color"],
    );
    palette.window_text = color_from(
        ini,
        &["colors:window", "window", "palette"],
        &["foregroundnormal", "window_text", "windowtext", "on_background"],
    );
    palette.base = color_from(
        ini,
        &["colors:view", "view", "palette", "colorscheme"],
        &["backgroundnormal", "base", "base_color", "surface", "background"],
    );
    palette.text = color_from(
        ini,
        &["colors:view", "view", "palette", "colorscheme"],
        &["foregroundnormal", "text", "on_surface", "on_background"],
    );
    palette.alternate_base = color_from(
        ini,
        &["colors:view", "view", "palette"],
        &["backgroundalternate", "alternate_base", "alternatebase"],
    );
    palette.button = color_from(
        ini,
        &["colors:button", "button", "palette"],
        &["backgroundnormal", "button", "button_color"],
    );
    palette.button_text = color_from(
        ini,
        &["colors:button", "button", "palette"],
        &["foregroundnormal", "button_text", "buttontext"],
    );
    palette.highlight = color_from(
        ini,
        &["colors:selection", "selection", "palette", "colorscheme"],
        &["backgroundnormal", "highlight", "accent", "primary", "selection"],
    );
    palette.highlighted_text = color_from(
        ini,
        &["colors:selection", "selection", "palette", "colorscheme"],
        &["foregroundnormal", "highlighted_text", "highlightedtext", "on_primary"],
    );
    palette.link = color_from(
        ini,
        &["colors:view", "view", "palette", "colorscheme"],
        &["foregroundlink", "link", "link_color"],
    );
    palette.tooltip_base = color_from(
        ini,
        &["colors:tooltip", "tooltip", "palette"],
        &["backgroundnormal", "tooltip_base", "tooltipbase"],
    );
    palette.tooltip_text = color_from(
        ini,
        &["colors:tooltip", "tooltip", "palette"],
        &["foregroundnormal", "tooltip_text", "tooltiptext"],
    );

    // Some Matugen templates use Material-style names rather than the Qt role
    // names. Read these when they are present in a color scheme file.
    set_if_missing(
        &mut palette.window,
        color_from(ini, &["colorscheme", "matugen", "palette"], &["surface", "background"]),
    );
    set_if_missing(
        &mut palette.window_text,
        color_from(ini, &["colorscheme", "matugen", "palette"], &["on_surface", "on_background"]),
    );
    set_if_missing(
        &mut palette.highlight,
        color_from(ini, &["colorscheme", "matugen", "palette"], &["primary", "accent"]),
    );
    set_if_missing(
        &mut palette.highlighted_text,
        color_from(ini, &["colorscheme", "matugen", "palette"], &["on_primary"]),
    );
    set_if_missing(
        &mut palette.link,
        color_from(ini, &["colorscheme", "matugen", "palette"], &["primary", "link"]),
    );

    // qt5ct/qt6ct normally store the three QPalette groups as color lists.
    for section in ["colorscheme", "palette"] {
        if let Some(colors) = ini_value(ini, section, "active_colors") {
            fill_from_qt_role_list(&mut palette, &color_list(colors));
            break;
        }
    }

    palette.dark = palette
        .window
        .as_deref()
        .or(palette.base.as_deref())
        .and_then(color_is_dark)
        .or_else(|| palette.name.as_deref().map(|n| n.to_lowercase().contains("dark")));
    palette
}

fn parse_kde_palette(path: &Path) -> Option<QtPalette> {
    let ini = read_ini(path)?;
    let name = ini_value(&ini, "general", "colorscheme").map(|v| unquote(v).to_string());
    let palette = palette_from_ini(&ini, name);
    palette_has_colors(&palette).then_some(palette)
}

fn kdeglobals_path() -> Option<PathBuf> {
    let path = config_root().join("kdeglobals");
    path.is_file().then_some(path)
}

fn with_known_extensions(path: &Path) -> Vec<PathBuf> {
    if path.extension().is_some() {
        return vec![path.to_path_buf()];
    }
    ["conf", "colors", "ini"]
        .iter()
        .map(|ext| path.with_extension(ext))
        .collect()
}

fn resolve_qtct_scheme(config_root: &Path, backend: &str, raw: &str) -> Option<PathBuf> {
    let raw = unquote(raw);
    if raw.is_empty() {
        return None;
    }
    let expanded = if let Some(rest) = raw.strip_prefix("~/") {
        dirs::home_dir()?.join(rest)
    } else {
        PathBuf::from(raw)
    };

    let mut candidates = Vec::new();
    if expanded.is_absolute() {
        candidates.extend(with_known_extensions(&expanded));
    } else {
        let backend_dir = config_root.join(backend);
        candidates.extend(with_known_extensions(&backend_dir.join(&expanded)));
        candidates.extend(with_known_extensions(&backend_dir.join("colors").join(&expanded)));
        candidates.extend(with_known_extensions(&config_root.join(&expanded)));

        if let Some(data_home) = std::env::var_os("XDG_DATA_HOME") {
            let data_root = PathBuf::from(data_home).join(backend);
            candidates.extend(with_known_extensions(&data_root.join(&expanded)));
            candidates.extend(with_known_extensions(&data_root.join("colors").join(&expanded)));
        }
        candidates.extend(with_known_extensions(
            &PathBuf::from("/usr/share").join(backend).join("colors").join(&expanded),
        ));
    }
    candidates.into_iter().find(|path| path.is_file())
}

/// The `[appearance] color_scheme` name from a qt5ct/qt6ct config file.
fn qtct_scheme_name(ini: &Ini) -> Option<String> {
    ini_value(ini, "appearance", "color_scheme")
        .or_else(|| ini_value(ini, "appearance", "colorscheme"))
        .map(|s| unquote(s).to_string())
}

fn qtct_backend_order() -> Vec<&'static str> {
    let platform_theme = std::env::var("QT_QPA_PLATFORMTHEME")
        .unwrap_or_default()
        .to_lowercase();
    if platform_theme.contains("qt5ct") {
        vec!["qt5ct", "qt6ct"]
    } else if platform_theme.contains("qt6ct") {
        vec!["qt6ct", "qt5ct"]
    } else {
        vec!["qt6ct", "qt5ct"]
    }
}

fn parse_qtct_palette(config_root: &Path, backend: &str) -> Option<QtPalette> {
    let config_file = config_root.join(backend).join(format!("{backend}.conf"));
    let config_ini = read_ini(&config_file);
    let scheme_name = config_ini.as_ref().and_then(qtct_scheme_name);

    let scheme_file = scheme_name
        .as_deref()
        .and_then(|name| resolve_qtct_scheme(config_root, backend, name));
    let scheme_palette = scheme_file.as_deref().and_then(|path| {
        let ini = read_ini(path)?;
        let name = path
            .file_stem()
            .and_then(|stem| stem.to_str())
            .map(str::to_string)
            .or_else(|| scheme_name.clone());
        Some(palette_from_ini(&ini, name))
    });

    let config_palette = config_ini.as_ref().map(|ini| {
        palette_from_ini(ini, scheme_name.clone().or_else(|| Some(backend.to_string())))
    });
    let mut palette = scheme_palette.or(config_palette)?;
    if !palette_has_colors(&palette) {
        return None;
    }
    if palette.name.is_none() {
        palette.name = scheme_name;
    }
    Some(palette)
}

fn read_qtct_palette() -> Option<QtPalette> {
    let config_root = config_dir()?;
    qtct_backend_order()
        .into_iter()
        .find_map(|backend| parse_qtct_palette(&config_root, backend))
}

fn pick_palette(kde: Option<QtPalette>, qtct: Option<QtPalette>, is_kde: bool) -> Option<QtPalette> {
    // Plasma's kdeglobals is authoritative on Plasma. On other desktops, the
    // explicitly selected qt5ct/qt6ct scheme is the better match for Qt apps.
    if is_kde {
        kde.or(qtct)
    } else {
        qtct.or(kde)
    }
}

// ─── Desktop mode / accent ───────────────────────────────────────────────────

fn parse_gnome_accent(value: &str) -> Option<String> {
    let name = unquote(value);
    let hex = match name {
        "blue" => "#3584e4",
        "teal" => "#2190a4",
        "green" => "#3a944a",
        "yellow" => "#c88800",
        "orange" => "#ed5b00",
        "red" => "#e62d42",
        "pink" => "#d56199",
        "purple" => "#9141ac",
        "slate" => "#6f8396",
        _ => return color_to_hex(name),
    };
    Some(hex.to_string())
}

fn gsetting(schema: &str, key: &str) -> Option<String> {
    let output = std::process::Command::new("gsettings")
        .args(["get", schema, key])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

// ─── Composition ─────────────────────────────────────────────────────────────

/// Read every theme source and merge them in the order documented at the top
/// of this file. `source = …` in theme.conf narrows which layers are consulted.
pub fn get_system_theme() -> SystemTheme {
    let rice = read_rice_config();
    let wants = |layer: &str| rice.source == "auto" || rice.source == layer;

    let desktop = std::env::var("XDG_CURRENT_DESKTOP")
        .unwrap_or_default()
        .to_lowercase();
    let is_kde = desktop.contains("kde") || desktop.contains("plasma");

    let kde_path = kdeglobals_path();
    let kde_ini = kde_path.as_deref().and_then(read_ini);
    let kde_scheme = kde_ini
        .as_ref()
        .and_then(|ini| ini_value(ini, "general", "colorscheme"))
        .map(|value| unquote(value).to_string());
    let kde_palette = kde_path.as_deref().and_then(parse_kde_palette);
    let qt_palette = pick_palette(kde_palette.clone(), read_qtct_palette(), is_kde);

    let mut layers: Vec<(&str, QtPalette)> = vec![("explicit", rice.explicit.clone())];
    if wants("matugen") {
        if let Some(palette) = read_matugen_palette(&rice.matugen_file) {
            layers.push(("matugen", palette));
        }
    }
    if wants("qt") {
        if let Some(palette) = qt_palette.clone() {
            layers.push(("qt", palette));
        }
    }
    if wants("gtk") {
        let palette = gtk_palette();
        if palette_has_colors(&palette) {
            layers.push(("gtk", palette));
        }
    }

    let mut merged = QtPalette::default();
    let mut source = "builtin".to_string();
    for (name, layer) in layers {
        if !palette_has_colors(&layer) {
            continue;
        }
        if source == "builtin" {
            source = name.to_string();
        }
        fill_missing(&mut merged, &layer);
    }
    let palette = palette_has_colors(&merged).then(|| {
        merged.dark = merged
            .window
            .as_deref()
            .or(merged.base.as_deref())
            .and_then(color_is_dark);
        merged
    });

    // Preserve the desktop's normal Auto mode, including GNOME's named accent
    // colors. A Qt palette is also a useful accent source on tiling WMs.
    let gnome_color_scheme = gsetting("org.gnome.desktop.interface", "color-scheme");
    let gnome_accent = gsetting("org.gnome.desktop.interface", "accent-color")
        .and_then(|value| parse_gnome_accent(&value));
    let kde_accent = kde_palette.as_ref().and_then(|p| p.highlight.clone());
    let accent = palette
        .as_ref()
        .and_then(|p| p.highlight.clone())
        .or(kde_accent)
        .or(gnome_accent);

    let dark = if is_kde {
        kde_palette
            .as_ref()
            .and_then(|p| p.dark)
            .or_else(|| kde_scheme.as_deref().map(|name| name.to_lowercase().contains("dark")))
            .or_else(|| qt_palette.as_ref().and_then(|p| p.dark))
            .unwrap_or(true)
    } else if let Some(color_scheme) = gnome_color_scheme {
        // gsettings uses 'default', 'prefer-dark', or 'prefer-light'.
        color_scheme.contains("dark")
    } else if let Some(gtk_theme) = gsetting("org.gnome.desktop.interface", "gtk-theme") {
        !gtk_theme.is_empty() && gtk_theme.to_lowercase().contains("dark")
    } else if let Ok(gtk_theme) = std::env::var("GTK_THEME") {
        gtk_theme.to_lowercase().contains("dark")
    } else {
        palette.as_ref().and_then(|p| p.dark).unwrap_or(true)
    };

    SystemTheme {
        dark,
        accent,
        palette,
        source,
        tokens: ThemeTokens {
            config_path: theme_config_path().to_string_lossy().to_string(),
            radius: rice.radius,
            font: rice.font,
            mono: rice.mono,
            font_size: rice.font_size,
            motion_reduced: rice.motion_reduced,
            speed: rice.speed,
        },
    }
}

// ─── Live updates ────────────────────────────────────────────────────────────

/// Files whose change should refresh the theme. Matugen, Qt, GTK, and KDE all
/// rewrite files in place, so modification times are the simplest reliable signal.
fn watched_paths() -> Vec<PathBuf> {
    let root = config_root();
    let rice = read_rice_config();
    let mut paths = vec![
        theme_config_path(),
        rice.matugen_file,
        root.join("kdeglobals"),
        root.join("gtk-4.0").join("gtk.css"),
        root.join("gtk-3.0").join("gtk.css"),
    ];
    for backend in ["qt5ct", "qt6ct"] {
        let conf = root.join(backend).join(format!("{backend}.conf"));
        let scheme = read_ini(&conf)
            .and_then(|ini| qtct_scheme_name(&ini))
            .and_then(|name| resolve_qtct_scheme(&root, backend, &name));
        paths.push(conf);
        paths.extend(scheme);
    }
    paths
}

type Stamp = Vec<(PathBuf, Option<(SystemTime, u64)>)>;

fn stamp() -> Stamp {
    watched_paths()
        .into_iter()
        .map(|path| {
            let modified = std::fs::metadata(&path)
                .ok()
                .and_then(|meta| Some((meta.modified().ok()?, meta.len())));
            (path, modified)
        })
        .collect()
}

/// Polls the theme files on a background thread and calls `on_change` with a
/// fresh theme whenever one of them changes. Cheap enough to run all the time:
/// one metadata call per file every 1.5 s, and no subprocesses unless a change occurs.
pub fn spawn_watcher<F>(on_change: F)
where
    F: Fn(SystemTheme) + Send + 'static,
{
    std::thread::spawn(move || {
        let mut last = stamp();
        loop {
            std::thread::sleep(Duration::from_millis(1500));
            let current = stamp();
            if current != last {
                last = current;
                on_change(get_system_theme());
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::{color_is_dark, color_to_hex, css_color, palette_from_ini, parse_ini, resolve_define, strip_inline_comment, section_palette};
    use std::collections::HashMap;

    #[test]
    fn normalizes_qt_and_kde_colors() {
        // Qt's #AARRGGBB drops the leading alpha byte.
        assert_eq!(color_to_hex("#ff1a2b3c"), Some("#1a2b3c".into()));
        assert_eq!(color_to_hex("#abc"), Some("#aabbcc".into()));
        assert_eq!(color_to_hex("239, 241, 245"), Some("#eff1f5".into()));
        assert_eq!(color_to_hex("not a color"), None);
    }

    #[test]
    fn gtk_css_colors_keep_rgb_and_drop_trailing_alpha() {
        assert_eq!(css_color("#1a2b3cff"), Some("#1a2b3c".into()));
        assert_eq!(css_color("rgb(20, 30, 40)"), Some("#141e28".into()));
    }

    #[test]
    fn inline_comments_do_not_cut_hex_colors() {
        assert_eq!(strip_inline_comment("#141318  # background"), "#141318");
        assert_eq!(strip_inline_comment("#141318"), "#141318");
        assert_eq!(strip_inline_comment("42 #tail"), "42 #tail");
    }

    #[test]
    fn resolves_gtk_define_references() {
        let mut defines = HashMap::new();
        defines.insert("accent_bg_color".to_string(), "@primary".to_string());
        defines.insert("primary".to_string(), "#d0bcff".to_string());
        assert_eq!(resolve_define("@accent_bg_color", &defines), Some("#d0bcff".into()));
    }

    #[test]
    fn parses_kde_color_roles() {
        let ini = parse_ini(
            "[General]\nColorScheme=Matugen\n[Colors:Window]\nBackgroundNormal=20,30,40\nForegroundNormal=240,240,240\n[Colors:Selection]\nBackgroundNormal=#d080e0\nForegroundNormal=#101010\n",
        );
        let palette = palette_from_ini(&ini, Some("Matugen".into()));
        assert_eq!(palette.window.as_deref(), Some("#141e28"));
        assert_eq!(palette.window_text.as_deref(), Some("#f0f0f0"));
        assert_eq!(palette.highlight.as_deref(), Some("#d080e0"));
        assert_eq!(palette.highlighted_text.as_deref(), Some("#101010"));
    }

    #[test]
    fn explicit_palette_section_reads_the_same_role_names() {
        let ini = parse_ini("[palette]\nsource = matugen\nwindow = #101010  # bg\nhighlight = #ff8800\n");
        let palette = section_palette(&ini, "palette");
        assert_eq!(palette.window.as_deref(), Some("#101010"));
        assert_eq!(palette.highlight.as_deref(), Some("#ff8800"));
        assert_eq!(palette.link, None);
    }

    #[test]
    fn maps_qtct_active_color_roles() {
        let colors = (0..20)
            .map(|role| format!("#ff{role:02x}{role:02x}{role:02x}"))
            .collect::<Vec<_>>()
            .join(", ");
        let ini = parse_ini(&format!("[ColorScheme]\nactive_colors={colors}\n"));
        let palette = palette_from_ini(&ini, Some("Matugen".into()));
        assert_eq!(palette.window_text.as_deref(), Some("#000000"));
        assert_eq!(palette.button.as_deref(), Some("#010101"));
        assert_eq!(palette.base.as_deref(), Some("#090909"));
        assert_eq!(palette.window.as_deref(), Some("#0a0a0a"));
        assert_eq!(palette.highlight.as_deref(), Some("#0c0c0c"));
        assert_eq!(palette.tooltip_text.as_deref(), Some("#131313"));
    }

    #[test]
    fn derives_light_or_dark_from_surface() {
        assert_eq!(color_is_dark("#101010"), Some(true));
        assert_eq!(color_is_dark("#f0f0f0"), Some(false));
    }
}

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde::Serialize;

/// The color roles that can be read from KDE/Qt color schemes and mapped onto
/// Screen AI's WebView UI. A native Qt widget style itself cannot style HTML.
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

#[derive(Serialize, Clone, Debug)]
pub struct SystemTheme {
    pub dark: bool,
    /// Accent/selection color as #rrggbb when the desktop exposes one.
    pub accent: Option<String>,
    /// Qt/KDE palette roles, if a configured color scheme could be read.
    pub palette: Option<QtPalette>,
}

type Ini = HashMap<String, HashMap<String, String>>;

fn config_dir() -> Option<PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(dirs::config_dir)
}

fn kdeglobals_path() -> Option<PathBuf> {
    config_dir()
        .map(|dir| dir.join("kdeglobals"))
        .filter(|path| path.is_file())
}

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
            .insert(key.trim().to_lowercase(), value.trim().to_string());
    }
    ini
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

/// Converts KDE's `r,g,b` values and Qt/CSS hex colors to CSS-friendly
/// #rrggbb. Alpha is dropped for #RGBA and Qt's #AARRGGBB forms.
fn color_to_hex(value: &str) -> Option<String> {
    let value = unquote(value);
    let value = value.strip_prefix("rgb(").and_then(|v| v.strip_suffix(')')).unwrap_or(value);

    if let Some(hex) = value.strip_prefix('#') {
        let hex = hex.trim();
        let expanded = match hex.len() {
            3 => {
                let mut result = String::with_capacity(6);
                for ch in hex.chars() {
                    result.push(ch);
                    result.push(ch);
                }
                result
            }
            4 => {
                let mut result = String::with_capacity(6);
                for ch in hex.chars().take(3) {
                    result.push(ch);
                    result.push(ch);
                }
                result // CSS #RGBA -> #RRGGBB
            }
            6 => hex.to_string(),
            8 => hex[2..].to_string(), // #AARRGGBB -> #RRGGBB
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

fn read_ini(path: &Path) -> Option<Ini> {
    let text = std::fs::read_to_string(path).ok()?;
    Some(parse_ini(&text))
}

fn parse_kde_palette(path: &Path) -> Option<QtPalette> {
    let ini = read_ini(path)?;
    let name = ini_value(&ini, "general", "colorscheme").map(|v| unquote(v).to_string());
    let palette = palette_from_ini(&ini, name);
    palette_has_colors(&palette).then_some(palette)
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
    let scheme_name = config_ini.as_ref().and_then(|ini| {
        ini_value(ini, "appearance", "color_scheme")
            .or_else(|| ini_value(ini, "appearance", "colorscheme"))
            .map(|s| unquote(s).to_string())
    });

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

fn color_is_dark(hex: &str) -> Option<bool> {
    let hex = color_to_hex(hex)?;
    let r = u8::from_str_radix(&hex[1..3], 16).ok()? as f32;
    let g = u8::from_str_radix(&hex[3..5], 16).ok()? as f32;
    let b = u8::from_str_radix(&hex[5..7], 16).ok()? as f32;
    Some((0.299 * r + 0.587 * g + 0.114 * b) < 128.0)
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

/// Read the user's desktop mode/accent and, separately, the active Qt palette.
/// Matugen-generated themes work when Matugen writes to kdeglobals or to the
/// active qt5ct/qt6ct color-scheme file; Matugen has no single universal output
/// path, so unrelated custom template files are intentionally not guessed.
pub fn get_system_theme() -> SystemTheme {
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
    let qtct_palette = read_qtct_palette();
    let palette = pick_palette(kde_palette.clone(), qtct_palette, is_kde);

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
            .or_else(|| palette.as_ref().and_then(|p| p.dark))
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

    SystemTheme { dark, accent, palette }
}

#[cfg(test)]
mod tests {
    use super::{color_is_dark, color_to_hex, palette_from_ini, parse_ini};

    #[test]
    fn normalizes_qt_and_kde_colors() {
        assert_eq!(color_to_hex("#AARRGGBB"), None);
        assert_eq!(color_to_hex("#ff1a2b3c"), Some("#1a2b3c".into()));
        assert_eq!(color_to_hex("#abc"), Some("#aabbcc".into()));
        assert_eq!(color_to_hex("239, 241, 245"), Some("#eff1f5".into()));
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

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::path::PathBuf;
use std::sync::Mutex;
use std::time::Duration;

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, LogicalPosition, LogicalSize, Manager, Position, Size, State, WebviewWindow};

// ─── Settings ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default = "d_provider")]
    pub provider: String,
    #[serde(default)]
    pub api_key: String,
    #[serde(default = "d_base")]
    pub base_url: String,
    #[serde(default = "d_model")]
    pub model: String,
    #[serde(default = "d_pos")]
    pub position: String,
    #[serde(default = "d_tokens")]
    pub max_tokens: u32,
    #[serde(default = "d_opacity")]
    pub bg_opacity: u8,
    #[serde(default = "d_font")]
    pub font_family: String,
    #[serde(default = "d_theme")]
    pub theme: String,
}

fn d_provider() -> String {
    "openai".into()
}
fn d_base() -> String {
    "https://api.openai.com/v1".into()
}
fn d_model() -> String {
    "gpt-4o-mini".into()
}
fn d_pos() -> String {
    "bottom-right".into()
}
fn d_tokens() -> u32 {
    800
}
fn d_opacity() -> u8 {
    100
}
fn d_font() -> String {
    "libron".into()
}
fn d_theme() -> String {
    "auto".into()
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            provider: d_provider(),
            api_key: String::new(),
            base_url: d_base(),
            model: d_model(),
            position: d_pos(),
            max_tokens: d_tokens(),
            bg_opacity: d_opacity(),
            font_family: d_font(),
            theme: d_theme(),
        }
    }
}

pub struct AppState {
    pub client: reqwest::Client,
    #[allow(dead_code)]
    pub last_prompt: Mutex<String>,
    pub current_thumb: Mutex<String>,
    pub initial_view: Mutex<String>,
    pub shown: std::sync::atomic::AtomicBool,
    pub layer: std::sync::atomic::AtomicBool,
}

fn config_path() -> PathBuf {
    let base = dirs::config_dir().unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("screen-ai").join("settings.json")
}

fn tmp_full() -> PathBuf {
    std::env::temp_dir().join("screen-ai-full.png")
}
fn tmp_send() -> PathBuf {
    std::env::temp_dir().join("screen-ai-send.jpg")
}

#[tauri::command]
fn get_settings() -> Settings {
    let p = config_path();
    if let Ok(bytes) = std::fs::read(&p) {
        if let Ok(s) = serde_json::from_slice::<Settings>(&bytes) {
            return s;
        }
    }
    Settings::default()
}

#[tauri::command]
fn save_settings(settings: Settings) -> Result<(), String> {
    let p = config_path();
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_string_pretty(&settings).map_err(|e| e.to_string())?;
    std::fs::write(&p, json).map_err(|e| e.to_string())?;
    Ok(())
}

// ─── Screenshots (X11 + Wayland) ─────────────────────────────────────────────

/// Unified screenshot capture: prioritizes fast native tools (grim on Wayland, maim/scrot on X11), then fallbacks.
fn capture_screen(full: &PathBuf) -> Result<(), String> {
    let is_wayland = std::env::var("WAYLAND_DISPLAY").is_ok()
        || std::env::var("XDG_SESSION_TYPE")
            .map(|s| s.to_lowercase() == "wayland")
            .unwrap_or(false);

    if is_wayland {
        let s = full.to_string_lossy().to_string();
        if let Ok(status) = std::process::Command::new("grim")
            .arg("-t")
            .arg("png")
            .arg(&s)
            .status()
        {
            if status.success() && full.exists() {
                return Ok(());
            }
        }
    }

    capture_cli(full).or_else(|_| capture_xcap(full))
}

/// Fallback path: shell out to whatever the distro / compositor provides.
fn capture_cli(full: &PathBuf) -> Result<(), String> {
    let s = full.to_string_lossy().to_string();
    let attempts: Vec<(&str, Vec<&str>)> = vec![
        ("grim", vec!["-t", "png", s.as_str()]),
        ("gnome-screenshot", vec!["-f", s.as_str()]),
        ("spectacle", vec!["-b", "-n", "-o", s.as_str()]),
        ("xfce4-screenshooter", vec!["-f", "-s", s.as_str()]),
        ("scrot", vec![s.as_str()]),
        ("maim", vec![s.as_str()]),
        ("import", vec!["-window", "root", s.as_str()]),
    ];
    for (prog, args) in attempts {
        match std::process::Command::new(prog).args(&args).output() {
            Ok(o) if o.status.success() && full.exists() => return Ok(()),
            _ => continue,
        }
    }
    Err("screenshot failed: no working backend (tried grim, gnome-screenshot, spectacle, scrot, maim, import, xcap)".into())
}

/// Last resort: in-process xcap capture (X11 direct; Wayland via portal).
fn capture_xcap(full: &PathBuf) -> Result<(), String> {
    let monitors = xcap::Monitor::all().map_err(|e| format!("xcap monitors: {e}"))?;
    let mon = monitors.into_iter().next().ok_or("xcap: no monitor")?;
    let img = mon
        .capture_image()
        .map_err(|e| format!("xcap capture: {e}"))?;
    img.save(full).map_err(|e| format!("xcap save: {e}"))?;
    Ok(())
}

/// Downscale for the vision API + build a tiny data-URL thumbnail for the ask bar.
fn process_images(full: &PathBuf, send: &PathBuf) -> Result<String, String> {
    let img = image::open(full).map_err(|e| format!("open shot: {e}"))?;
    let (w, h) = (img.width(), img.height());

    // Send version: longest edge 1568px (keeps vision calls fast + cheap).
    let scale = 1568.0 / (w.max(h).max(1) as f32);
    let send_img = if scale < 1.0 {
        img.resize(
            (w as f32 * scale) as u32,
            (h as f32 * scale) as u32,
            image::imageops::FilterType::Lanczos3,
        )
    } else {
        img.clone()
    };
    send_img
        .save_with_format(send, image::ImageFormat::Jpeg)
        .map_err(|e| format!("save send-img: {e}"))?;

    // Thumbnail: 160px wide PNG data URL.
    let tw = 160u32;
    let th = (h * tw / w.max(1)).clamp(1, 160);
    let thumb = img.resize_exact(tw, th, image::imageops::FilterType::Triangle);
    let mut buf: Vec<u8> = Vec::new();
    {
        let mut cur = std::io::Cursor::new(&mut buf);
        thumb
            .write_to(&mut cur, image::ImageFormat::Png)
            .map_err(|e| format!("thumb encode: {e}"))?;
    }
    Ok(format!("data:image/png;base64,{}", B64.encode(&buf)))
}

// ─── Overlay window ──────────────────────────────────────────────────────────
//
// On Wayland compositors that speak wlr-layer-shell (niri, Hyprland, sway,
// KDE Plasma, river, labwc, …) the overlay is a persistent, full-screen,
// transparent layer surface. It is NEVER unmapped, so the compositor never
// plays open/close animations; the UI animates itself. Everything outside the
// visible card is excluded from the input region, so clicks pass straight
// through to the windows underneath.
//
// Everywhere else (X11, GNOME/Mutter) it falls back to a plain borderless
// window that is shown/hidden, with the same input-shape trick.

use std::sync::atomic::Ordering;

#[derive(Deserialize, Debug, Clone)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[derive(Deserialize, Debug, Clone)]
pub struct Turn {
    pub role: String,
    pub text: String,
}

fn is_layer(app: &AppHandle) -> bool {
    app.try_state::<AppState>()
        .map(|s| s.layer.load(Ordering::Relaxed))
        .unwrap_or(false)
}

fn is_shown(app: &AppHandle) -> bool {
    app.try_state::<AppState>()
        .map(|s| s.shown.load(Ordering::Relaxed))
        .unwrap_or(false)
}

fn set_shown(app: &AppHandle, v: bool) {
    if let Some(s) = app.try_state::<AppState>() {
        s.shown.store(v, Ordering::Relaxed);
    }
}

/// Run `f` on the GTK main thread with the overlay's toplevel window.
fn with_gtk<F>(app: &AppHandle, f: F)
where
    F: FnOnce(&gtk::ApplicationWindow) + Send + 'static,
{
    let Some(win) = app.get_webview_window("main") else {
        return;
    };
    let _ = app.run_on_main_thread(move || {
        if let Ok(g) = win.gtk_window() {
            f(&g);
        }
    });
}

fn apply_region(g: &gtk::ApplicationWindow, rects: &[Rect]) {
    use gtk::prelude::*;
    let Some(gdk) = g.window() else {
        return;
    };
    let region = cairo::Region::create();
    for r in rects {
        let _ = region.union_rectangle(&cairo::RectangleInt::new(
            r.x,
            r.y,
            r.width.max(1),
            r.height.max(1),
        ));
    }
    gdk.input_shape_combine_region(&region, 0, 0);
}

fn set_keyboard(app: &AppHandle, mode: &'static str) {
    if !is_layer(app) {
        return;
    }
    with_gtk(app, move |g| {
        use gtk_layer_shell::{KeyboardMode, LayerShell};
        g.set_keyboard_mode(match mode {
            "exclusive" => KeyboardMode::Exclusive,
            "ondemand" => KeyboardMode::OnDemand,
            _ => KeyboardMode::None,
        });
    });
}

/// Make the (non-layer) fallback window cover the whole monitor.
fn fit_fullscreen(window: &WebviewWindow) {
    let mon = window
        .current_monitor()
        .ok()
        .flatten()
        .or_else(|| window.primary_monitor().ok().flatten())
        .or_else(|| {
            window
                .available_monitors()
                .ok()
                .and_then(|v| v.into_iter().next())
        });
    let (mx, my, mw, mh) = if let Some(m) = mon {
        let p = m.position();
        let s = m.size();
        let sf = m.scale_factor();
        (
            p.x as f64 / sf,
            p.y as f64 / sf,
            s.width as f64 / sf,
            s.height as f64 / sf,
        )
    } else {
        (0.0, 0.0, 1920.0, 1080.0)
    };
    let _ = window.set_size(Size::Logical(LogicalSize { width: mw, height: mh }));
    let _ = window.set_position(Position::Logical(LogicalPosition { x: mx, y: my }));
}

/// Plain-window path (GNOME/Mutter, X11, or layer-shell disabled): cover the
/// current monitor, pin above everything, and fight for focus — Mutter will
/// not grant it on its own when the summon arrives from another process.
fn show_fallback(window: &WebviewWindow) {
    fit_fullscreen(window);
    // No-op on Wayland, enforced on X11 — harmless to always set.
    let _ = window.set_always_on_top(true);
    let _ = window.set_skip_taskbar(true);
    let _ = window.show();
    let _ = window.set_focus();
    if !window.is_focused().unwrap_or(true) {
        let _ =
            window.request_user_attention(Some(tauri::UserAttentionType::Informational));
    }
}

/// Turn the Wayland toplevel into a full-screen overlay layer surface.
/// Must run before the window is first realized.
fn init_layer_shell(app: &AppHandle) {
    use gtk::prelude::*;
    use gtk_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

    let wayland = std::env::var("WAYLAND_DISPLAY").is_ok()
        || std::env::var("XDG_SESSION_TYPE")
            .map(|s| s.eq_ignore_ascii_case("wayland"))
            .unwrap_or(false);
    if !wayland || std::env::var("SCREEN_AI_NO_LAYER").is_ok() {
        return;
    }
    let Some(win) = app.get_webview_window("main") else {
        return;
    };
    let Ok(g) = win.gtk_window() else {
        return;
    };
    if !gtk_layer_shell::is_supported() {
        eprintln!("screen-ai: compositor has no layer-shell, using plain window");
        return;
    }
    g.init_layer_shell();
    if !g.is_layer_window() {
        eprintln!("screen-ai: layer-shell init failed, using plain window");
        return;
    }
    g.set_layer(Layer::Overlay);
    g.set_namespace("screen-ai");
    for e in [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right] {
        g.set_anchor(e, true);
    }
    g.set_exclusive_zone(-1);
    g.set_keyboard_mode(KeyboardMode::None);
    g.realize();
    apply_region(&g, &[]); // nothing clickable until the UI says so
    if let Some(s) = app.try_state::<AppState>() {
        s.layer.store(true, Ordering::Relaxed);
    }
    let _ = win.show();
}

fn show_overlay(app: &AppHandle) {
    set_shown(app, true);
    if is_layer(app) {
        // Exclusive grabs keyboard focus right away; once we have it, relax to
        // on-demand so the user can click into other windows normally.
        set_keyboard(app, "exclusive");
        let a = app.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(500));
            if is_shown(&a) {
                set_keyboard(&a, "ondemand");
            }
        });
    } else if let Some(w) = app.get_webview_window("main") {
        show_fallback(&w);
    }
}

fn hide_overlay_now(app: &AppHandle) {
    set_shown(app, false);
    if is_layer(app) {
        with_gtk(app, |g| apply_region(g, &[]));
        set_keyboard(app, "none");
    } else if let Some(w) = app.get_webview_window("main") {
        let _ = w.hide();
    }
}

#[tauri::command]
fn set_interactive_regions(app: AppHandle, regions: Vec<Rect>) {
    with_gtk(&app, move |g| apply_region(g, &regions));
}

#[tauri::command]
fn overlay_hidden(app: AppHandle) {
    hide_overlay_now(&app);
}

/// Summon the overlay (screenshot first, then show) or dismiss it if it is
/// already up. `view` is "ask" or "settings".
fn summon(app: &AppHandle, view: &str) {
    let Some(window) = app.get_webview_window("main") else {
        return;
    };
    if is_shown(app) {
        let _ = window.emit(if view == "settings" { "show-settings" } else { "request-hide" }, ());
        return;
    }

    let full = tmp_full();
    let send = tmp_send();
    let _ = std::fs::remove_file(&full);
    let _ = std::fs::remove_file(&send);

    // Capture BEFORE showing so the overlay is never in the shot.
    let thumb = match capture_screen(&full) {
        Ok(()) => process_images(&full, &send).unwrap_or_default(),
        Err(e) => {
            eprintln!("screen-ai capture failed: {e}");
            String::new()
        }
    };

    if let Some(state) = app.try_state::<AppState>() {
        if let Ok(mut t) = state.current_thumb.lock() {
            *t = thumb.clone();
        }
        if let Ok(mut v) = state.initial_view.lock() {
            *v = view.to_string();
        }
    }

    show_overlay(app);
    let _ = window.emit("summon", serde_json::json!({ "thumb": thumb, "view": view }));
}

fn do_toggle(app: &AppHandle) {
    summon(app, "ask");
}

fn show_settings(app: &AppHandle) {
    summon(app, "settings");
}

#[tauri::command]
fn get_initial_state(app: AppHandle, state: State<'_, AppState>) -> serde_json::Value {
    let settings = get_settings();
    let thumb = state.current_thumb.lock().map(|t| t.clone()).unwrap_or_default();
    let view = state.initial_view.lock().map(|v| v.clone()).unwrap_or_else(|_| "ask".into());
    let needs_key = settings.provider != "ollama" && settings.api_key.trim().is_empty();
    serde_json::json!({
        "settings": settings,
        "thumb": thumb,
        "view": view,
        "shown": is_shown(&app),
        "needs_key": needs_key,
    })
}

#[tauri::command]
fn quit_app(app: AppHandle) {
    app.exit(0);
}

#[tauri::command]
async fn fetch_models(
    state: State<'_, AppState>,
    provider: String,
    base_url: String,
    api_key: String,
) -> Result<Vec<String>, String> {
    let client = &state.client;
    let p = provider.to_lowercase();
    let key = api_key.trim();
    let url = base_url.trim().trim_end_matches('/');

    match p.as_str() {
        "gemini" => {
            if key.is_empty() {
                return Err("API key is required to fetch Gemini models".into());
            }
            let req_url = format!("{url}/v1beta/models?key={key}");
            let res = client
                .get(&req_url)
                .send()
                .await
                .map_err(|e| format!("Failed to reach Gemini: {e}"))?;
            if !res.status().is_success() {
                let status = res.status();
                let txt = res.text().await.unwrap_or_default();
                return Err(format!("{status}: {txt}"));
            }
            let json: serde_json::Value = res.json().await.map_err(|e| e.to_string())?;
            let mut models = Vec::new();
            if let Some(list) = json.get("models").and_then(|m| m.as_array()) {
                for item in list {
                    if let Some(name) = item.get("name").and_then(|n| n.as_str()) {
                        let clean = name.strip_prefix("models/").unwrap_or(name);
                        if let Some(methods) = item.get("supportedGenerationMethods").and_then(|s| s.as_array()) {
                            let can_generate = methods.iter().any(|m| m.as_str() == Some("generateContent"));
                            if can_generate && (clean.contains("gemini") || clean.contains("flash") || clean.contains("pro")) {
                                models.push(clean.to_string());
                            }
                        } else {
                            models.push(clean.to_string());
                        }
                    }
                }
            }
            models.sort_by(|a, b| b.cmp(a));
            Ok(models)
        }
        "anthropic" => {
            if key.is_empty() {
                return Err("API key is required to fetch Anthropic models".into());
            }
            let req_url = format!("{url}/v1/models");
            let res = client
                .get(&req_url)
                .header("x-api-key", key)
                .header("anthropic-version", "2023-06-01")
                .send()
                .await
                .map_err(|e| format!("Failed to reach Anthropic: {e}"))?;
            if !res.status().is_success() {
                let status = res.status();
                let txt = res.text().await.unwrap_or_default();
                return Err(format!("{status}: {txt}"));
            }
            let json: serde_json::Value = res.json().await.map_err(|e| e.to_string())?;
            let mut models = Vec::new();
            if let Some(data) = json.get("data").and_then(|d| d.as_array()) {
                for item in data {
                    if let Some(id) = item.get("id").and_then(|i| i.as_str()) {
                        models.push(id.to_string());
                    }
                }
            }
            models.sort();
            Ok(models)
        }
        "ollama" => {
            let req_url = format!("{url}/api/tags");
            let res = client
                .get(&req_url)
                .send()
                .await
                .map_err(|e| format!("Failed to reach Ollama: {e}"))?;
            if !res.status().is_success() {
                let status = res.status();
                let txt = res.text().await.unwrap_or_default();
                return Err(format!("{status}: {txt}"));
            }
            let json: serde_json::Value = res.json().await.map_err(|e| e.to_string())?;
            let mut models = Vec::new();
            if let Some(list) = json.get("models").and_then(|m| m.as_array()) {
                for item in list {
                    if let Some(name) = item.get("name").and_then(|n| n.as_str()) {
                        models.push(name.to_string());
                    }
                }
            }
            Ok(models)
        }
        _ => {
            let req_url = if url.ends_with("/models") {
                url.to_string()
            } else if url.ends_with("/v1") {
                format!("{url}/models")
            } else {
                format!("{url}/v1/models")
            };
            let mut req = client.get(&req_url);
            if !key.is_empty() {
                req = req.header("Authorization", format!("Bearer {key}"));
            }
            let res = req
                .send()
                .await
                .map_err(|e| format!("Failed to fetch models from {req_url}: {e}"))?;
            if !res.status().is_success() {
                let status = res.status();
                let txt = res.text().await.unwrap_or_default();
                return Err(format!("{status}: {txt}"));
            }
            let json: serde_json::Value = res.json().await.map_err(|e| e.to_string())?;
            let mut models = Vec::new();
            if let Some(data) = json.get("data").and_then(|d| d.as_array()) {
                for item in data {
                    if let Some(id) = item.get("id").and_then(|i| i.as_str()) {
                        models.push(id.to_string());
                    }
                }
            }
            models.sort();
            Ok(models)
        }
    }
}

// ─── AI streaming (BYOK) ─────────────────────────────────────────────────────

/// Pump a `text/event-stream` response, emitting `ai-chunk` per text delta.
async fn pump_sse<F>(resp: reqwest::Response, window: &WebviewWindow, mut on_text: F) -> Result<(), String>
where
    F: FnMut(&str) -> Option<String>,
{
    if !resp.status().is_success() {
        let code = resp.status();
        let body = resp.text().await.unwrap_or_default();
        let msg = serde_json::from_str::<serde_json::Value>(&body)
            .ok()
            .and_then(|v| {
                v.get("error")
                    .and_then(|e| {
                        e.get("message")
                            .and_then(|m| m.as_str().map(|s| s.to_string()))
                    })
                    .or_else(|| {
                        v.get("message")
                            .and_then(|m| m.as_str().map(|s| s.to_string()))
                    })
            })
            .unwrap_or_else(|| body.chars().take(300).collect());
        let msg = if msg.trim().is_empty() {
            format!("request failed ({code}) — check key / model / endpoint")
        } else {
            format!("{code}: {msg}")
        };
        return Err(msg);
    }

    let mut stream = resp.bytes_stream();
    let mut buf = String::new();
    while let Some(chunk) = stream.next().await {
        let bytes = chunk.map_err(|e| format!("stream read: {e}"))?;
        buf.push_str(&String::from_utf8_lossy(&bytes));
        while let Some(idx) = buf.find('\n') {
            let line: String = buf.drain(..=idx).collect();
            let line = line.trim();
            let Some(payload) = line.strip_prefix("data:") else {
                continue;
            };
            let payload = payload.trim();
            if payload.is_empty() || payload == "[DONE]" {
                continue;
            }
            if let Some(text) = on_text(payload) {
                if !text.is_empty() {
                    let _ = window.emit("ai-chunk", text);
                }
            }
        }
    }
    Ok(())
}

const SYSTEM_PROMPT: &str = "You are a fast, concise assistant living in a screen overlay. The user's screenshot is attached to their first message. Answer directly about what is on screen, formatting with Markdown (tables and fenced code blocks are rendered). Never reply with only a safety verdict.";

/// OpenAI-compatible: OpenAI, OpenRouter, Groq, Ollama, Together, custom…
async fn stream_openai_compat(
    client: &reqwest::Client,
    window: &WebviewWindow,
    s: &Settings,
    turns: &[Turn],
    b64: &str,
) -> Result<(), String> {
    let url = format!("{}/chat/completions", s.base_url.trim_end_matches('/'));
    let mut messages: Vec<serde_json::Value> =
        vec![serde_json::json!({ "role": "system", "content": SYSTEM_PROMPT })];
    for (i, t) in turns.iter().enumerate() {
        if i == 0 {
            messages.push(serde_json::json!({
                "role": "user",
                "content": [
                    { "type": "text", "text": t.text },
                    { "type": "image_url", "image_url": { "url": format!("data:image/jpeg;base64,{b64}") } }
                ]
            }));
        } else {
            messages.push(serde_json::json!({ "role": t.role, "content": t.text }));
        }
    }
    let body = serde_json::json!({
        "model": s.model,
        "stream": true,
        "max_tokens": s.max_tokens,
        "messages": messages
    });
    let mut req = client.post(&url).json(&body);
    if !s.api_key.trim().is_empty() {
        req = req.header("Authorization", format!("Bearer {}", s.api_key.trim()));
    }
    if s.provider == "openrouter" {
        req = req
            .header("HTTP-Referer", "https://github.com/bhavyam2468/screen-ai")
            .header("X-Title", "Screen AI");
    }
    let resp = req.send().await.map_err(|e| format!("request: {e}"))?;
    pump_sse(resp, window, |payload| {
        let v: serde_json::Value = serde_json::from_str(payload).ok()?;
        v.get("choices")?
            .get(0)?
            .get("delta")?
            .get("content")?
            .as_str()
            .map(|t| t.to_string())
    })
    .await
}

async fn stream_anthropic(
    client: &reqwest::Client,
    window: &WebviewWindow,
    s: &Settings,
    turns: &[Turn],
    b64: &str,
) -> Result<(), String> {
    let url = format!("{}/v1/messages", s.base_url.trim_end_matches('/'));
    let messages: Vec<serde_json::Value> = turns
        .iter()
        .enumerate()
        .map(|(i, t)| {
            if i == 0 {
                serde_json::json!({
                    "role": "user",
                    "content": [
                        { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": b64 } },
                        { "type": "text", "text": t.text }
                    ]
                })
            } else {
                serde_json::json!({ "role": t.role, "content": t.text })
            }
        })
        .collect();
    let body = serde_json::json!({
        "model": s.model,
        "max_tokens": s.max_tokens,
        "stream": true,
        "system": SYSTEM_PROMPT,
        "messages": messages
    });
    let resp = client
        .post(&url)
        .header("x-api-key", s.api_key.trim())
        .header("anthropic-version", "2023-06-01")
        .header("content-type", "application/json")
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("request: {e}"))?;
    pump_sse(resp, window, |payload| {
        let v: serde_json::Value = serde_json::from_str(payload).ok()?;
        if v.get("type")?.as_str()? != "content_block_delta" {
            return None;
        }
        let d = v.get("delta")?;
        if d.get("type")?.as_str()? != "text_delta" {
            return None;
        }
        d.get("text")?.as_str().map(|x| x.to_string())
    })
    .await
}

async fn stream_gemini(
    client: &reqwest::Client,
    window: &WebviewWindow,
    s: &Settings,
    turns: &[Turn],
    b64: &str,
) -> Result<(), String> {
    let url = format!(
        "{}/v1beta/models/{}:streamGenerateContent?alt=sse&key={}",
        s.base_url.trim_end_matches('/'),
        s.model,
        s.api_key.trim()
    );
    let contents: Vec<serde_json::Value> = turns
        .iter()
        .enumerate()
        .map(|(i, t)| {
            let role = if t.role == "assistant" { "model" } else { "user" };
            if i == 0 {
                serde_json::json!({
                    "role": role,
                    "parts": [
                        { "text": t.text },
                        { "inline_data": { "mime_type": "image/jpeg", "data": b64 } }
                    ]
                })
            } else {
                serde_json::json!({ "role": role, "parts": [{ "text": t.text }] })
            }
        })
        .collect();
    let body = serde_json::json!({
        "systemInstruction": { "parts": [{ "text": SYSTEM_PROMPT }] },
        "generationConfig": { "maxOutputTokens": s.max_tokens },
        "contents": contents
    });
    let resp = client
        .post(&url)
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("request: {e}"))?;
    pump_sse(resp, window, |payload| {
        let v: serde_json::Value = serde_json::from_str(payload).ok()?;
        v.get("candidates")?
            .get(0)?
            .get("content")?
            .get("parts")?
            .get(0)?
            .get("text")?
            .as_str()
            .map(|t| t.to_string())
    })
    .await
}

#[tauri::command]
async fn ask_ai(
    window: WebviewWindow,
    state: State<'_, AppState>,
    prompt: String,
    history: Vec<Turn>,
) -> Result<(), String> {
    {
        let mut lp = state.last_prompt.lock().map_err(|e| e.to_string())?;
        *lp = prompt.clone();
    }

    let settings = get_settings();
    if settings.provider != "ollama" && settings.api_key.trim().is_empty() {
        return Err("No API key — open settings (gear icon) and paste one.".into());
    }

    let send = tmp_send();
    let img_bytes = std::fs::read(&send)
        .map_err(|_| "No screenshot captured — dismiss and summon again.".to_string())?;
    let b64 = B64.encode(&img_bytes);

    let mut turns = history;
    turns.push(Turn { role: "user".into(), text: prompt });

    let client = state.client.clone();
    tauri::async_runtime::spawn(async move {
        let res = match settings.provider.as_str() {
            "anthropic" => stream_anthropic(&client, &window, &settings, &turns, &b64).await,
            "gemini" => stream_gemini(&client, &window, &settings, &turns, &b64).await,
            _ => stream_openai_compat(&client, &window, &settings, &turns, &b64).await,
        };
        match res {
            Ok(()) => {
                let _ = window.emit("ai-done", ());
            }
            Err(e) => {
                let _ = window.emit("ai-error", e);
            }
        }
    });
    Ok(())
}

// ─── Tray ────────────────────────────────────────────────────────────────────

fn tray_icon_image() -> tauri::image::Image<'static> {
    // 32px violet→cyan orb, generated — no asset file needed at runtime.
    let size = 32u32;
    let mut rgba = Vec::with_capacity((size * size * 4) as usize);
    for y in 0..size {
        for x in 0..size {
            let dx = x as f32 - 15.5;
            let dy = y as f32 - 15.5;
            let d = (dx * dx + dy * dy).sqrt() / 15.5;
            let edge = (1.0 - d).clamp(0.0, 1.0);
            let alpha = (edge.powf(0.7) * 255.0) as u8;
            let t = x as f32 / 31.0;
            let r = (139.0 + (34.0 - 139.0) * t) as u8;
            let g = (92.0 + (211.0 - 92.0) * t) as u8;
            let b = (246.0 + (238.0 - 246.0) * t) as u8;
            rgba.extend_from_slice(&[r, g, b, alpha]);
        }
    }
    tauri::image::Image::new_owned(rgba, size, size)
}

// ─── Updates ─────────────────────────────────────────────────────────────────

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct UpdateInfo {
    pub current_version: String,
    pub latest_version: String,
    pub has_update: bool,
    pub release_notes: String,
    pub download_url: String,
    pub checksum_url: String,
    pub published_at: String,
}

fn normalize_version(v: &str) -> String {
    let core = v
        .trim()
        .trim_start_matches(&['v', 'V'][..])
        .split(&['-', '+'][..])
        .next()
        .unwrap_or("0");
    let mut parts: Vec<String> = core
        .split('.')
        .take(3)
        .map(|p| {
            let digits: String = p.chars().take_while(|c| c.is_ascii_digit()).collect();
            if digits.is_empty() {
                "0".to_string()
            } else {
                digits
            }
        })
        .collect();
    while parts.len() < 3 {
        parts.push("0".to_string());
    }
    parts.join(".")
}

fn is_newer_version(latest: &str, current: &str) -> bool {
    match (
        semver::Version::parse(&normalize_version(latest)),
        semver::Version::parse(&normalize_version(current)),
    ) {
        (Ok(l), Ok(c)) => l > c,
        // Unparseable tags: any non-empty difference counts as an update.
        _ => !latest.trim().is_empty() && latest.trim() != current.trim(),
    }
}

#[tauri::command]
async fn check_for_updates(state: tauri::State<'_, AppState>) -> Result<UpdateInfo, String> {
    let current_version = env!("CARGO_PKG_VERSION").to_string();
    let url = "https://api.github.com/repos/bhavyam2468/screen-ai/releases/latest";
    let res = state
        .client
        .get(url)
        .header("User-Agent", "screen-ai")
        .header("Accept", "application/vnd.github.v3+json")
        .send()
        .await
        .map_err(|e| format!("Failed to contact GitHub: {e}"))?;

    if !res.status().is_success() {
        return Err(format!("GitHub returned HTTP {}", res.status()));
    }

    let json: serde_json::Value = res
        .json()
        .await
        .map_err(|e| format!("Failed to parse release info: {e}"))?;

    let tag = json["tag_name"].as_str().unwrap_or("").to_string();
    let release_notes = json["body"].as_str().unwrap_or("").to_string();
    let published_at = json["published_at"].as_str().unwrap_or("").to_string();

    let mut download_url = String::new();
    let mut tarball_name = String::new();
    if let Some(assets) = json["assets"].as_array() {
        for asset in assets {
            if let Some(name) = asset["name"].as_str() {
                if name.ends_with(".tar.gz") {
                    if let Some(dl) = asset["browser_download_url"].as_str() {
                        download_url = dl.to_string();
                        tarball_name = name.to_string();
                        break;
                    }
                }
            }
        }
    }

    if download_url.is_empty() && !tag.is_empty() {
        tarball_name = "screen-ai-x86_64-linux.tar.gz".to_string();
        download_url = format!(
            "https://github.com/bhavyam2468/screen-ai/releases/download/{tag}/{tarball_name}"
        );
    }

    // Checksum sidecar: `<tarball>.sha256`, or a repo-level sums file.
    let mut checksum_url = String::new();
    if let Some(assets) = json["assets"].as_array() {
        let want_sidecar = format!("{tarball_name}.sha256");
        for asset in assets {
            let Some(name) = asset["name"].as_str() else {
                continue;
            };
            let lower = name.to_lowercase();
            let is_sums = name == want_sidecar
                || lower == "sha256sums"
                || lower == "sha256sums.txt"
                || lower == "checksums.txt"
                || lower == "checksums-sha256.txt";
            if is_sums {
                if let Some(dl) = asset["browser_download_url"].as_str() {
                    checksum_url = dl.to_string();
                    break;
                }
            }
        }
    }
    if checksum_url.is_empty() && !download_url.is_empty() {
        // Conventional fallback: sidecar published next to the tarball.
        checksum_url = format!("{download_url}.sha256");
    }

    let has_update = is_newer_version(&tag, &current_version);

    Ok(UpdateInfo {
        current_version,
        latest_version: tag,
        has_update,
        release_notes,
        download_url,
        checksum_url,
        published_at,
    })
}

/// Only GitHub-controlled hosts may serve self-update payloads.
fn check_update_url(url: &str) -> Result<(), String> {
    let rest = url
        .strip_prefix("https://")
        .ok_or_else(|| "Update URL must use https".to_string())?;
    let host = rest.split('/').next().unwrap_or("").to_lowercase();
    let host = host.split('@').next_back().unwrap_or("");
    let host = host.split(':').next().unwrap_or("");
    let ok = host == "github.com"
        || host == "api.github.com"
        || host == "objects.githubusercontent.com"
        || host == "release-assets.githubusercontent.com"
        || host.ends_with(".githubusercontent.com");
    if ok {
        Ok(())
    } else {
        Err(format!(
            "Refusing to download update from untrusted host '{host}'"
        ))
    }
}

/// Compare downloaded bytes against the release's sha256 sidecar.
/// A missing/unreadable sidecar warns but allows install (old releases predate
/// checksums); a present-but-mismatched checksum is a hard failure.
async fn verify_checksum(
    client: &reqwest::Client,
    checksum_url: &str,
    bytes: &[u8],
) -> Result<(), String> {
    if checksum_url.trim().is_empty() {
        eprintln!("screen-ai: no checksum published for this release, skipping verification");
        return Ok(());
    }
    let res = client
        .get(checksum_url)
        .header("User-Agent", "screen-ai")
        .send()
        .await
        .map_err(|e| format!("Failed to fetch checksum: {e}"))?;
    if !res.status().is_success() {
        eprintln!(
            "screen-ai: checksum sidecar unavailable (HTTP {}), skipping verification",
            res.status()
        );
        return Ok(());
    }
    let text = res.text().await.unwrap_or_default();
    // Formats: "<hex>" or "<hex>  <filename>" (sha256sum style).
    let expected = text.split_whitespace().next().unwrap_or("").to_lowercase();
    if expected.len() != 64 || !expected.chars().all(|c| c.is_ascii_hexdigit()) {
        eprintln!("screen-ai: checksum sidecar malformed, skipping verification");
        return Ok(());
    }
    let actual = {
        use sha2::{Digest, Sha256};
        format!("{:x}", Sha256::digest(bytes))
    };
    if actual != expected {
        return Err(
            "Checksum mismatch — update payload failed its integrity check, refusing to install"
                .into(),
        );
    }
    Ok(())
}

#[tauri::command]
async fn install_update(
    download_url: String,
    checksum_url: String,
    state: tauri::State<'_, AppState>,
) -> Result<String, String> {
    if download_url.is_empty() {
        return Err("Download URL is empty".into());
    }
    check_update_url(&download_url)?;
    if !checksum_url.trim().is_empty() {
        check_update_url(&checksum_url)?;
    }

    let current_exe = std::env::current_exe().map_err(|e| format!("Cannot locate current executable: {e}"))?;
    let home_bin = dirs::home_dir().map(|h| h.join(".local/bin/screen-ai"));
    let target_path = if current_exe.exists() && current_exe.to_string_lossy().contains(".local/bin") {
        current_exe.clone()
    } else if let Some(ref hb) = home_bin {
        if hb.exists() {
            hb.clone()
        } else {
            current_exe.clone()
        }
    } else {
        current_exe.clone()
    };

    let temp_dir = std::env::temp_dir().join(format!("screen-ai-update-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&temp_dir);
    std::fs::create_dir_all(&temp_dir).map_err(|e| format!("Failed to create temp dir: {e}"))?;

    let archive_path = temp_dir.join("update.tar.gz");
    let resp = state
        .client
        .get(&download_url)
        .header("User-Agent", "screen-ai")
        .send()
        .await
        .map_err(|e| format!("Failed to download update: {e}"))?;

    if !resp.status().is_success() {
        return Err(format!("Download failed with HTTP {}", resp.status()));
    }

    let bytes = resp.bytes().await.map_err(|e| format!("Failed to read response: {e}"))?;
    if bytes.len() > 512 * 1024 * 1024 {
        let _ = std::fs::remove_dir_all(&temp_dir);
        return Err("Update payload implausibly large, refusing to install".into());
    }
    if let Err(e) = verify_checksum(&state.client, &checksum_url, &bytes).await {
        let _ = std::fs::remove_dir_all(&temp_dir);
        return Err(e);
    }
    std::fs::write(&archive_path, &bytes).map_err(|e| format!("Failed to save archive: {e}"))?;

    // Inspect the listing before extracting: refuse anything but the binary.
    let listing = std::process::Command::new("tar")
        .args(["-tzf", archive_path.to_str().unwrap_or("")])
        .output()
        .map_err(|e| format!("Failed to list update archive: {e}"))?;
    if !listing.status.success() {
        let _ = std::fs::remove_dir_all(&temp_dir);
        return Err("Update archive is not a valid tarball".into());
    }
    for entry in String::from_utf8_lossy(&listing.stdout).lines() {
        let e = entry.trim().trim_start_matches("./");
        if e.is_empty() || e == "." {
            continue;
        }
        if e != "screen-ai" {
            let _ = std::fs::remove_dir_all(&temp_dir);
            return Err(format!("Update archive contains unexpected file '{e}', refusing to install"));
        }
    }

    let status = std::process::Command::new("tar")
        .args(["-xzf", archive_path.to_str().unwrap(), "-C", temp_dir.to_str().unwrap()])
        .status()
        .map_err(|e| format!("Failed to execute tar: {e}"))?;

    if !status.success() {
        return Err("tar extraction failed".into());
    }

    let new_binary = temp_dir.join("screen-ai");
    if !new_binary.exists() {
        return Err("Update package does not contain 'screen-ai' binary".into());
    }

    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(&new_binary, std::fs::Permissions::from_mode(0o755));

    let parent = target_path.parent().unwrap_or(&temp_dir);
    let staged = parent.join(format!(".screen-ai.new-{}", std::process::id()));
    std::fs::copy(&new_binary, &staged).map_err(|e| format!("Failed to stage binary: {e}"))?;
    let _ = std::fs::set_permissions(&staged, std::fs::Permissions::from_mode(0o755));

    std::fs::rename(&staged, &target_path).map_err(|e| {
        let _ = std::fs::remove_file(&staged);
        format!("Failed to install binary to {}: {e}", target_path.display())
    })?;

    let _ = std::fs::remove_dir_all(&temp_dir);

    Ok(format!("Updated successfully to {}", target_path.display()))
}

#[tauri::command]
fn restart_app() -> Result<(), String> {
    let current_exe = std::env::current_exe().map_err(|e| format!("Cannot locate current executable: {e}"))?;
    let home_bin = dirs::home_dir().map(|h| h.join(".local/bin/screen-ai"));
    let target_path = if let Some(ref hb) = home_bin {
        if hb.exists() { hb.clone() } else { current_exe }
    } else {
        current_exe
    };

    std::process::Command::new(&target_path)
        .arg("--toggle")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| format!("Failed to launch updated binary: {e}"))?;

    std::process::exit(0);
}

// ─── System theme (follow the desktop: KDE/Qt, GNOME/GTK) ────────────────────────

#[derive(serde::Serialize, Clone, Debug)]
pub struct SystemTheme {
    pub dark: bool,
    /// Accent/selection color as #rrggbb when the desktop exposes one.
    pub accent: Option<String>,
}

fn kdeglobals_path() -> Option<PathBuf> {
    if let Ok(c) = std::env::var("XDG_CONFIG_HOME") {
        let p = PathBuf::from(c).join("kdeglobals");
        if p.exists() {
            return Some(p);
        }
    }
    dirs::home_dir()
        .map(|h| h.join(".config/kdeglobals"))
        .filter(|p| p.exists())
}

/// Minimal INI lookup: value of `key` inside `[section]`.
fn ini_lookup(path: &PathBuf, section: &str, key: &str) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    let mut in_section = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') && line.ends_with(']') && line.len() >= 2 {
            in_section = line[1..line.len() - 1].eq_ignore_ascii_case(section);
            continue;
        }
        if !in_section {
            continue;
        }
        let Some((k, v)) = line.split_once('=') else {
            continue;
        };
        if k.trim().eq_ignore_ascii_case(key) {
            return Some(v.trim().to_string());
        }
    }
    None
}

fn gsetting(schema: &str, key: &str) -> Option<String> {
    let out = std::process::Command::new("gsettings")
        .args(["get", schema, key])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn rgb_to_hex(rgb: &str) -> Option<String> {
    let parts: Vec<u8> = rgb
        .split(',')
        .filter_map(|p| p.trim().parse().ok())
        .collect();
    if parts.len() < 3 {
        return None;
    }
    Some(format!("#{:02x}{:02x}{:02x}", parts[0], parts[1], parts[2]))
}

#[tauri::command]
fn get_system_theme() -> SystemTheme {
    let desktop = std::env::var("XDG_CURRENT_DESKTOP")
        .unwrap_or_default()
        .to_lowercase();
    let is_kde = desktop.contains("kde") || desktop.contains("plasma");
    // Plasma's selection color doubles as an accent even on non-KDE desktops
    // that theme Qt via kdeglobals (Hyprland + qt6ct, etc.).
    let kde_accent = kdeglobals_path()
        .and_then(|p| ini_lookup(&p, "Colors:Selection", "BackgroundNormal"))
        .as_deref()
        .and_then(rgb_to_hex);

    // KDE Plasma: ColorScheme name decides light/dark.
    if is_kde {
        if let Some(p) = kdeglobals_path() {
            let scheme = ini_lookup(&p, "General", "ColorScheme").unwrap_or_default();
            if !scheme.is_empty() {
                return SystemTheme {
                    dark: scheme.to_lowercase().contains("dark"),
                    accent: kde_accent,
                };
            }
        }
    }

    // GNOME / GTK desktops.
    if let Some(cs) = gsetting("org.gnome.desktop.interface", "color-scheme") {
        // 'default' | 'prefer-dark' | 'prefer-light'
        let accent = gsetting("org.gnome.desktop.interface", "accent-color")
            .and_then(|a| match a.trim().trim_matches('\'') {
                "blue" => Some("#3584e4".to_string()),
                "teal" => Some("#2190a4".to_string()),
                "green" => Some("#3a944a".to_string()),
                "yellow" => Some("#c88800".to_string()),
                "orange" => Some("#ed5b00".to_string()),
                "red" => Some("#e62d42".to_string()),
                "pink" => Some("#d56199".to_string()),
                "purple" => Some("#9141ac".to_string()),
                "slate" => Some("#6f8396".to_string()),
                _ => None,
            })
            .or(kde_accent.clone());
        return SystemTheme {
            dark: cs.contains("dark"),
            accent,
        };
    }
    if let Some(gtk_theme) = gsetting("org.gnome.desktop.interface", "gtk-theme") {
        if !gtk_theme.is_empty() {
            return SystemTheme {
                dark: gtk_theme.to_lowercase().contains("dark"),
                accent: kde_accent.clone(),
            };
        }
    }

    // Last resorts: GTK_THEME override, then assume dark (the native look).
    if let Ok(t) = std::env::var("GTK_THEME") {
        if !t.is_empty() {
            return SystemTheme {
                dark: t.to_lowercase().contains("dark"),
                accent: kde_accent.clone(),
            };
        }
    }
    SystemTheme {
        dark: true,
        accent: kde_accent,
    }
}

// ─── App ─────────────────────────────────────────────────────────────────────

/// gtk-layer-shell must be loaded before libwayland-client. Re-exec once with
/// it preloaded so that holds no matter how the binary was linked.
fn ensure_layer_preload() {
    use std::os::unix::process::CommandExt;
    if std::env::var("SCREEN_AI_PRELOAD").is_ok() || std::env::var("WAYLAND_DISPLAY").is_err() {
        return;
    }
    let Ok(exe) = std::env::current_exe() else {
        return;
    };
    let mut preload = "libgtk-layer-shell.so.0".to_string();
    if let Ok(existing) = std::env::var("LD_PRELOAD") {
        if !existing.is_empty() {
            preload = format!("{preload}:{existing}");
        }
    }
    let err = std::process::Command::new(exe)
        .args(std::env::args().skip(1))
        .env("SCREEN_AI_PRELOAD", "1")
        .env("LD_PRELOAD", preload)
        .exec();
    eprintln!("screen-ai: re-exec failed: {err}");
}

fn main() {
    ensure_layer_preload();
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .expect("http client");

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, argv, _cwd| {
            if argv.iter().any(|a| a == "--settings") {
                show_settings(app);
            } else {
                // Any second launch (notably `screen-ai --toggle`) wakes the overlay.
                do_toggle(app);
            }
        }))
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _shortcut, event| {
                    use tauri_plugin_global_shortcut::ShortcutState;
                    if matches!(event.state(), ShortcutState::Pressed) {
                        do_toggle(app);
                    }
                })
                .build(),
        )
        .manage(AppState {
            client,
            last_prompt: Mutex::new(String::new()),
            current_thumb: Mutex::new(String::new()),
            initial_view: Mutex::new("ask".to_string()),
            shown: std::sync::atomic::AtomicBool::new(false),
            layer: std::sync::atomic::AtomicBool::new(false),
        })
        .setup(|app| {
            init_layer_shell(app.handle());
            // Tray: click toggles, menu for settings/quit.
            use tauri::menu::{Menu, MenuItem};
            use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
            let tog = MenuItem::with_id(app.handle(), "toggle", "Ask about screen", true, None::<&str>)?;
            let set = MenuItem::with_id(app.handle(), "settings", "Settings", true, None::<&str>)?;
            let quit = MenuItem::with_id(app.handle(), "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app.handle(), &[&tog, &set, &quit])?;
            let _tray = TrayIconBuilder::new()
                .icon(tray_icon_image())
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => app.exit(0),
                    "settings" => show_settings(app),
                    "toggle" => do_toggle(app),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app_handle = tray.app_handle();
                        do_toggle(&app_handle);
                    }
                })
                .build(app.handle())?;

            // In-app global hotkey only where the platform allows it (X11).
            // On Wayland the user binds a system shortcut → `screen-ai --toggle`.
            let session = std::env::var("XDG_SESSION_TYPE")
                .unwrap_or_default()
                .to_lowercase();
            let is_wayland =
                session == "wayland" || std::env::var("WAYLAND_DISPLAY").is_ok();
            if !is_wayland {
                use tauri_plugin_global_shortcut::{
                    Code, GlobalShortcutExt, Modifiers, Shortcut,
                };
                let shortcut1 =
                    Shortcut::new(Some(Modifiers::SUPER | Modifiers::SHIFT), Code::KeyS);
                let shortcut2 =
                    Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::Space);
                let _ = app.global_shortcut().register(shortcut1);
                let _ = app.global_shortcut().register(shortcut2);
            }

            // First-run behaviour.
            let args: Vec<String> = std::env::args().collect();
            if args.iter().any(|a| a == "--toggle") {
                do_toggle(app.handle());
            } else if args.iter().any(|a| a == "--settings") {
                show_settings(app.handle());
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            get_initial_state,
            ask_ai,
            quit_app,
            fetch_models,
            set_interactive_regions,
            overlay_hidden,
            check_for_updates,
            install_update,
            restart_app,
            get_system_theme
        ])
        .run(tauri::generate_context!())
        .expect("error while running screen-ai");
}

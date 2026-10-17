#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::path::PathBuf;
use std::sync::Mutex;
use std::time::Duration;

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, LogicalPosition, LogicalSize, Manager, Position, Size, State, WebviewWindow};

mod theme;

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
    // 32px blue accent orb, generated — no asset file needed at runtime.
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
            let r = (57.0 + (130.0 - 57.0) * t) as u8;
            let g = (115.0 + (173.0 - 115.0) * t) as u8;
            let b = (209.0 + (255.0 - 209.0) * t) as u8;
            rgba.extend_from_slice(&[r, g, b, alpha]);
        }
    }
    tauri::image::Image::new_owned(rgba, size, size)
}

// ─── Source updates ───────────────────────────────────────────────────────────

#[derive(serde::Serialize, Clone, Debug)]
pub struct UpdateStatus {
    pub current_version: String,
    pub current_sha: String,
    pub update_available: bool,
    pub latest_sha: String,
    pub latest_message: String,
}

const REPO_API: &str = "https://api.github.com/repos/bhavyam2468/screen-ai";

fn app_version() -> String {
    let sha = env!("SCREEN_AI_COMMIT");
    let dirty = env!("SCREEN_AI_DIRTY") == "1";
    format!("v1.{}{}", sha, if dirty { "+dirty" } else { "" })
}

fn truncate_update_log(text: &str) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let start = lines.len().saturating_sub(24);
    lines[start..].join("\n")
}

#[tauri::command]
async fn check_for_updates(state: tauri::State<'_, AppState>) -> Result<UpdateStatus, String> {
    let response = state
        .client
        .get(format!("{REPO_API}/commits/main"))
        .header("User-Agent", "screen-ai-source-updater")
        .header("Accept", "application/vnd.github+json")
        .send()
        .await
        .map_err(|e| format!("Could not check GitHub for source updates: {e}"))?;
    if !response.status().is_success() {
        return Err(format!("GitHub returned HTTP {} while checking for updates", response.status()));
    }
    let json: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Could not read GitHub commit information: {e}"))?;
    let latest_sha = json["sha"]
        .as_str()
        .ok_or_else(|| "GitHub did not return the latest source commit SHA".to_string())?
        .to_string();
    let latest_message = json["commit"]["message"]
        .as_str()
        .unwrap_or("Latest source revision")
        .lines()
        .next()
        .unwrap_or("Latest source revision")
        .to_string();
    let current_sha = env!("SCREEN_AI_COMMIT").to_string();
    let update_available = env!("SCREEN_AI_DIRTY") == "1"
        || current_sha == "unknown"
        || !latest_sha.to_ascii_lowercase().starts_with(&current_sha.to_ascii_lowercase());

    Ok(UpdateStatus {
        current_version: app_version(),
        current_sha,
        update_available,
        latest_sha,
        latest_message,
    })
}

async fn run_source_update(source_ref: &str, label: &str) -> Result<String, String> {
    let install_path = std::env::current_exe()
        .map_err(|e| format!("Cannot locate the installed Screen AI executable: {e}"))?;
    let updater = install_path
        .parent()
        .map(|bin_dir| bin_dir.join("screen-ai-update"))
        .ok_or_else(|| "Cannot locate the installed Screen AI updater".to_string())?;
    if !updater.is_file() {
        return Err("The local source updater is missing. Re-run the Linux installer to install it.".into());
    }

    let output = tokio::process::Command::new("bash")
        .arg(&updater)
        .arg("--ref")
        .arg(source_ref)
        .arg("--install-path")
        .arg(&install_path)
        .output()
        .await
        .map_err(|e| format!("Could not start the source updater: {e}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let transcript = format!("{stdout}\n{stderr}");
    if !output.status.success() {
        let tail = truncate_update_log(&transcript);
        return Err(if tail.trim().is_empty() {
            format!("Source update failed with {}", output.status)
        } else {
            format!("Source update failed: {tail}")
        });
    }
    Ok(format!("Built {label} from GitHub source and installed at {}", install_path.display()))
}

#[tauri::command]
async fn update_from_source() -> Result<String, String> {
    run_source_update("main", "latest main").await
}

#[tauri::command]
async fn update_from_pr(state: State<'_, AppState>, pr_number: u64) -> Result<String, String> {
    if pr_number == 0 {
        return Err("Enter a valid Screen AI pull request number.".into());
    }
    let url = format!("{REPO_API}/pulls/{pr_number}");
    let response = state
        .client
        .get(url)
        .header("User-Agent", "screen-ai-source-updater")
        .header("Accept", "application/vnd.github+json")
        .send()
        .await
        .map_err(|e| format!("Could not fetch pull request #{pr_number} from GitHub: {e}"))?;
    if !response.status().is_success() {
        return Err(format!("GitHub returned HTTP {} for pull request #{pr_number}", response.status()));
    }
    let pull_request: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Could not read pull request #{pr_number} metadata: {e}"))?;
    let base_repo = pull_request["base"]["repo"]["full_name"].as_str().unwrap_or_default();
    if !base_repo.eq_ignore_ascii_case("bhavyam2468/screen-ai") {
        return Err(format!("Pull request #{pr_number} is not for bhavyam2468/screen-ai."));
    }
    let head_sha = pull_request["head"]["sha"]
        .as_str()
        .filter(|sha| sha.len() == 40 && sha.chars().all(|c| c.is_ascii_hexdigit()))
        .ok_or_else(|| format!("GitHub did not return a valid source commit for pull request #{pr_number}"))?;

    let label = format!("pull request #{pr_number}");
    run_source_update(head_sha, &label).await
}

#[tauri::command]
fn restart_app() -> Result<(), String> {
    let current_exe = std::env::current_exe().map_err(|e| format!("Cannot locate current executable: {e}"))?;
    let target = if current_exe.exists() {
        current_exe
    } else {
        let display = current_exe.to_string_lossy();
        let recovered = display.strip_suffix(" (deleted)").map(std::path::PathBuf::from);
        recovered.filter(|path| path.is_file()).ok_or_else(|| {
            "Updated binary could not be located; close Screen AI and launch it again from your app menu.".to_string()
        })?
    };

    // Let this instance exit before the replacement enters the single-instance
    // plugin. The executable path is passed as an argument, never interpolated
    // into shell source, so paths containing spaces remain safe.
    std::process::Command::new("sh")
        .arg("-c")
        .arg("sleep 0.4; exec \"$1\" --settings")
        .arg("screen-ai-restart")
        .arg(&target)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| format!("Failed to schedule the updated app restart: {e}"))?;
    std::process::exit(0);
}

// ─── System theme (follow the desktop: KDE/Qt, GNOME/GTK) ────────────────────

#[tauri::command]
fn get_system_theme() -> theme::SystemTheme {
    theme::get_system_theme()
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
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--help" || a == "-h") {
        println!(
            "screen-ai {}\n\nUsage:\n  screen-ai             start (runs in the tray)\n  screen-ai --toggle    summon/dismiss the overlay\n  screen-ai --settings  open settings\n  screen-ai --version   print version",
            app_version()
        );
        return;
    }
    if args.iter().any(|a| a == "--version" || a == "-V") {
        println!("screen-ai {}", app_version());
        return;
    }
    ensure_layer_preload();
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .expect("http client");

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, argv, _cwd| {
            if argv.iter().any(|a| a == "--settings") {
                show_settings(app);
            } else if argv.iter().any(|a| a == "--toggle") {
                do_toggle(app);
            }
            // Any other second launch (bare `screen-ai`, autostart races,
            // sway/i3 `exec` firing on every reload) is a deliberate no-op:
            // the app is already running, and toggling would be surprising.
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

            // Use in-app global shortcuts only as an X11 fallback when the
            // current desktop/compositor does not provide a native binding.
            // Installed sessions otherwise bind the configured command directly.
            let session = std::env::var("XDG_SESSION_TYPE")
                .unwrap_or_default()
                .to_lowercase();
            let is_wayland =
                session == "wayland" || std::env::var("WAYLAND_DISPLAY").is_ok();
            let desktop = std::env::var("XDG_CURRENT_DESKTOP")
                .or_else(|_| std::env::var("DESKTOP_SESSION"))
                .unwrap_or_default()
                .to_lowercase();
            let session_has_native_shortcuts = [
                "gnome", "unity", "budgie", "plasma", "kde", "cinnamon", "mate", "xfce",
                "i3", "sway", "river", "niri", "hypr",
            ]
            .iter()
            .any(|name| desktop.contains(*name))
                || [
                    "NIRI_SOCKET",
                    "HYPRLAND_INSTANCE_SIGNATURE",
                    "SWAYSOCK",
                    "I3SOCK",
                    "RIVER_SOCKET",
                ]
                .iter()
                .any(|name| std::env::var_os(*name).is_some());
            if !is_wayland && !session_has_native_shortcuts {
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
            update_from_source,
            update_from_pr,
            restart_app,
            get_system_theme
        ])
        .run(tauri::generate_context!())
        .expect("error while running screen-ai");
}

//! Desktop focus awareness for the Wayland overlay.
//!
//! Screen AI's overlay is a permanent wlr-layer-shell surface. Summoning it with
//! a hotkey asks the compositor for an *exclusive* keyboard grab so you can type
//! straight away — but an exclusive grab is sticky: niri, Hyprland and sway keep
//! handing the keyboard back to the layer surface even after you click a window
//! behind it, so the overlay swallows keys meant for other apps (including the
//! Enter that confirms an interactive screenshot).
//!
//! Those compositors publish focus changes on their IPC socket. This module
//! follows them and calls back whenever *something else* takes the keyboard, so
//! `main` can step the overlay down to `on-demand` interactivity. The card stays
//! visible and click-through, and clicking it hands the keyboard back — which is
//! exactly what layer-shell `on-demand` is for.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Desktop {
    Niri,
    Hyprland,
    Sway,
}

/// The running compositor, when it is one whose focus events we can follow.
pub fn detect() -> Option<Desktop> {
    if std::env::var_os("NIRI_SOCKET").is_some() {
        return Some(Desktop::Niri);
    }
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some() {
        return Some(Desktop::Hyprland);
    }
    if std::env::var_os("SWAYSOCK").is_some() {
        return Some(Desktop::Sway);
    }
    None
}

/// True when one event line means "another surface owns the keyboard now".
/// Events that report *no* focused window are ignored: clicking the overlay
/// itself (a layer surface, never a window) must not release its own keyboard.
fn focus_moved_away(desktop: Desktop, line: &str) -> bool {
    match desktop {
        // niri: {"WindowFocusChanged":{"id":7}} and
        // {"OverviewOpenedOrClosed":{"is_open":true}} — the overview needs the
        // keyboard for its search field.
        Desktop::Niri => match serde_json::from_str::<serde_json::Value>(line) {
            Ok(event) => {
                event["WindowFocusChanged"]["id"].is_u64()
                    || event["OverviewOpenedOrClosed"]["is_open"].as_bool() == Some(true)
            }
            Err(_) => false,
        },
        // hyprland: `activewindow>>class,title`; `activewindow>>,` means nothing
        // is focused (a layer surface or the desktop was clicked).
        Desktop::Hyprland => line
            .strip_prefix("activewindow>>")
            .map(|rest| !rest.trim_start_matches(',').trim().is_empty())
            .unwrap_or(false),
        // sway: {"change":"focus","container":{…}}; `container` is null when the
        // focus moved to nothing.
        Desktop::Sway => match serde_json::from_str::<serde_json::Value>(line) {
            Ok(event) => event["change"].as_str() == Some("focus") && event["container"].is_object(),
            Err(_) => false,
        },
    }
}

/// Follows a CLI event stream (`niri msg`, `swaymsg`) line by line. Returns
/// false when the program cannot be started at all, true when the stream ended
/// and reconnecting is worthwhile (compositor restart, CLI upgrade).
fn follow_command<F>(argv: &[&str], desktop: Desktop, on_focus_moved: &F) -> bool
where
    F: Fn(),
{
    let Ok(mut child) = Command::new(argv[0])
        .args(&argv[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return false;
    };
    let Some(stdout) = child.stdout.take() else {
        let _ = child.wait();
        return false;
    };
    for line in BufReader::new(stdout).lines() {
        let Ok(line) = line else { break };
        if focus_moved_away(desktop, &line) {
            on_focus_moved();
        }
    }
    let _ = child.wait();
    true
}

fn hyprland_socket() -> Option<PathBuf> {
    let signature = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").ok()?;
    let runtime = std::env::var("XDG_RUNTIME_DIR").ok()?;
    if signature.is_empty() || runtime.is_empty() {
        return None;
    }
    let socket = PathBuf::from(runtime)
        .join("hypr")
        .join(signature)
        .join(".socket2.sock");
    if socket.exists() {
        Some(socket)
    } else {
        None
    }
}

/// Reads Hyprland's plain-text event socket. A failed connect is transient (the
/// compositor is restarting), so the caller should retry.
fn follow_socket<F>(path: &Path, desktop: Desktop, on_focus_moved: &F) -> bool
where
    F: Fn(),
{
    let Ok(stream) = std::os::unix::net::UnixStream::connect(path) else {
        return true;
    };
    for line in BufReader::new(stream).lines() {
        let Ok(line) = line else { break };
        if focus_moved_away(desktop, &line) {
            on_focus_moved();
        }
    }
    true
}

/// Starts the watcher on a background thread and returns the desktop it is
/// following. `None` means the compositor publishes no focus events we can read,
/// so the caller keeps its existing behaviour.
pub fn spawn_watcher<F>(on_focus_moved: F) -> Option<Desktop>
where
    F: Fn() + Send + 'static,
{
    let desktop = detect()?;
    std::thread::spawn(move || loop {
        let retry = match desktop {
            Desktop::Niri => {
                follow_command(&["niri", "msg", "--json", "event-stream"], desktop, &on_focus_moved)
            }
            Desktop::Sway => {
                follow_command(&["swaymsg", "-t", "subscribe", "-m", "window"], desktop, &on_focus_moved)
            }
            Desktop::Hyprland => match hyprland_socket() {
                Some(path) => follow_socket(&path, desktop, &on_focus_moved),
                None => false,
            },
        };
        if !retry {
            return;
        }
        std::thread::sleep(Duration::from_secs(2));
    });
    Some(desktop)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn niri_focus_events_only_fire_for_a_real_window() {
        assert!(focus_moved_away(Desktop::Niri, r#"{"WindowFocusChanged":{"id":12}}"#));
        assert!(!focus_moved_away(Desktop::Niri, r#"{"WindowFocusChanged":{"id":null}}"#));
        assert!(focus_moved_away(
            Desktop::Niri,
            r#"{"OverviewOpenedOrClosed":{"is_open":true}}"#
        ));
        assert!(!focus_moved_away(
            Desktop::Niri,
            r#"{"OverviewOpenedOrClosed":{"is_open":false}}"#
        ));
        assert!(!focus_moved_away(Desktop::Niri, r#"{"WindowClosed":{"id":12}}"#));
        assert!(!focus_moved_away(Desktop::Niri, "not json"));
    }

    #[test]
    fn hyprland_focus_events_ignore_unfocused_notifications() {
        assert!(focus_moved_away(Desktop::Hyprland, "activewindow>>firefox,Docs"));
        assert!(!focus_moved_away(Desktop::Hyprland, "activewindow>>,"));
        assert!(!focus_moved_away(Desktop::Hyprland, "openlayer>>screen-ai"));
    }

    #[test]
    fn sway_focus_events_need_a_container() {
        assert!(focus_moved_away(
            Desktop::Sway,
            r#"{"change":"focus","container":{"app_id":"firefox"}}"#
        ));
        assert!(!focus_moved_away(Desktop::Sway, r#"{"change":"focus","container":null}"#));
        assert!(!focus_moved_away(Desktop::Sway, r#"{"change":"move","container":{}}"#));
    }
}

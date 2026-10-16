# Screen AI Overlay — Tech Stack Decision

**Goal:** Global hotkey → screenshot + prompt → LLM vision → streaming reply bubble in a corner. Minimal, ultra-polished, animated. Wayland + X11. BYOK. Auto-installing setup.

## Decision: Tauri v2 + React + Vite + Tailwind + Framer Motion

| Concern | Choice | Why |
|---|---|---|
| Shell | **Tauri v2** (Rust backend + WebKitGTK webview) | ~10MB binary vs ~150MB Electron. Native transparency + always-on-top + blur works on both X11 and Wayland. Rust gives easy screenshots, global shortcuts, single-instance CLI trigger. |
| UI | **React + Vite + TailwindCSS + Framer Motion** | Hot glassmorphism + spring animations are trivial. Markdown rendering via `react-markdown`. Single codebase for ask bar / reply bubble / settings (one window that morphs). |
| Screenshots | **`xcap` crate + CLI fallbacks** (`grim` / `gnome-screenshot` / `scrot` / `maim` / `import`) | `xcap` covers X11 natively and Wayland via PipeWire portal. Fallbacks cover wlroots (Hyprland/Sway), GNOME, KDE. Portal-first = no compositor-specific code. |
| Global invoke | **Single-instance CLI trigger** (`screen-ai --toggle`) + **Tauri global-shortcut on X11** | Wayland deliberately blocks background keyloggers/global hotkeys. The *correct* Wayland-native way is: user binds one key in GNOME/KDE/Hyprland settings → runs `screen-ai --toggle` → running instance wakes. Works everywhere, zero hacks. On X11 we additionally register the hotkey in-app. |
| LLM (BYOK) | **OpenAI-compatible + Anthropic native + Gemini native**, streaming SSE via `reqwest` | One code path covers OpenAI, OpenRouter, Groq, Together, Ollama (local, no key), any custom base URL. Plus native Anthropic + Gemini paths. Keys stored locally in `~/.config/screen-ai/settings.json`, never leave the machine except to the chosen provider. |
| Settings | JSON file in `~/.config/screen-ai/` | No DB, no cloud, instant. |
| Packaging | `setup.sh` (distro-detecting: apt/dnf/pacman/zypper) + `.desktop` + tray icon | Installs Rust, Node, WebKitGTK, portals, screenshot tools, builds release binary, installs to `~/.local/bin`, prints keybind instructions per DE. |

## Why not the alternatives

- **Electron:** 15x heavier, transparency/blur is flaky on Wayland, worse startup for an overlay you summon constantly.
- **Python + Qt/QML:** Great system integration, but "really hot" animated UI takes 3x the code; styling springs, markdown, streaming are all manual. Distribution (venv, Qt versions) is messier than one Rust binary.
- **GTK4/Adwaita alone:** Native but hard to make stunning; custom animations are painful.
- **Ulauncher/GNOME-extension:** Tied to one DE, can't do floating corner bubbles nicely.

## Architecture

```
┌─ System keybind (GNOME/KDE/Hyprland) ── runs `screen-ai --toggle`
│   (X11 alt: in-app global shortcut)
▼
┌──────────────────────────────────────────────┐
│ Tauri Rust backend (single instance)          │
│  • capture_screenshot → /tmp + thumb          │
│  • ask_ai(prompt+img) → SSE stream → events   │
│  • window morph: center ask ↔ corner reply    │
│  • settings.json read/write                   │
└──────────────┬───────────────────────────────┘
               │ invoke / events (ai-chunk/done/error)
▼
┌──────────────────────────────────────────────┐
│ React overlay (ONE transparent window)        │
│  ask view: pill input + 32px screenshot thumb │
│  reply view: 360px glass card, streams md     │
│  settings view: BYOK, model, position         │
└──────────────────────────────────────────────┘
```

## Window strategy: one morphing window

Instead of 3 windows (ask/reply/settings), we use **one transparent always-on-top window** that morphs:
- `ask` → 560×64 pill, screen-center, spring-in.
- `reply` → 380×auto card, bottom-right / bottom-left / bottom-center per setting.
- `settings` → 420×auto card, screen-center.

Fewer moving parts, one animation system, positioning via `window.set_position()`.

## Screenshot pipeline

1. Try `xcap` (X11 direct; Wayland via portal+PipeWire).
2. Fallbacks shell-out: `grim` → `gnome-screenshot` → `spectacle` → `scrot` → `maim` → `import`.
3. Downscale to max 1568px longest edge, JPEG q80 → keeps vision calls fast + cheap.
4. Original full-res saved to `/tmp/screen-ai-full.png` (for future "copy screenshot" use).

## What `setup.sh` installs

- Build: `rustup/cargo`, `nodejs/npm`
- Tauri webview: `webkit2gtk-4.1`, `gtk3`, `libayatana-appindicator3`, `librsvg`, `libssl`
- Screen capture: `xdg-desktop-portal{,-gtk,-kde}`, `pipewire`, `grim`+`slurp` (wlroots), `gnome-screenshot` (GNOME), `scrot`/`maim` (X11)
- Then: `npm i && cargo build --release`, install to `~/.local/bin/screen-ai`, write `.desktop`, print per-DE keybind recipe.

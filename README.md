# ✦ Screen AI

**Ask any AI about whatever is on your screen.** Instant capture · True click-passthrough · Morphing fluid dock · Bring your own key.

Works natively across **Niri**, **Hyprland**, **Sway**, **KDE Plasma**, **GNOME**, **X11**, and every Linux desktop.

```
███████╗ ██████╗██████╗ ███████╗███████╗███╗   ██╗    █████╗ ██╗
██╔════╝██╔════╝██╔══██╗██╔════╝██╔════╝████╗  ██║   ██╔══██╗██║
███████╗██║     ██████╔╝█████╗  █████╗  ██╔██╗ ██║   ███████║██║
╚════██║██║     ██╔══██╗██╔══╝  ██╔══╝  ██║╚██╗██║   ██╔══██║██║
███████║╚██████╗██║  ██║███████╗███████╗██║ ╚████║   ██║  ██║██║
╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝  ╚═╝╚═╝
```

[![Release](https://img.shields.io/github/v/release/bhavyam2468/screen-ai?color=22c55e&style=flat-square)](https://github.com/bhavyam2468/screen-ai/releases)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Wayland%20%7C%20X11-f59e0b?style=flat-square)](https://github.com/bhavyam2468/screen-ai)
[![Tauri](https://img.shields.io/badge/Tauri-v2-f97316?style=flat-square&logo=tauri&logoColor=white)](https://tauri.app)

---

## ⚡ Quick Install

Run this one-liner in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/bhavyam2468/screen-ai/main/install.sh | bash
```

The interactive installer will:
1. Detect your Linux distribution & desktop compositor.
2. Auto-install system dependencies (`gtk-layer-shell`, `webkit2gtk`, portals, screenshot tools) via `pacman`, `apt`, `dnf`, `zypper`, `xbps`, or `apk`.
3. Download the pre-built release binary (or compile from source if on an unsupported arch).
4. Run an interactive setup: choose your AI provider (Gemini, OpenAI, Anthropic, OpenRouter, Groq, or local Ollama), test your key, fetch and select available models, configure overlay position & background opacity.
5. Automatically configure global hotkeys and autostart for your specific window manager (Niri, Hyprland, Sway, i3, Plasma, GNOME, etc.).

---

## ✨ Highlights

- **Native Wayland Overlay (`gtk-layer-shell`)**: Operates on `Layer::Overlay` directly above all windows without spawning janky floating desktop frames or triggering window-zooming artifacts.
- **Dynamic Click Passthrough**: The input region precisely tracks the dock and chat bubble. Clicks anywhere outside the active UI pass directly through to your underlying editor, browser, or terminal.
- **Morphing Fluid Dock**: Seamlessly expands from a minimal bottom input bar into an upward-growing multi-turn chat panel using Spring physics (`[0.22, 1, 0.36, 1]` cubic bezier). No disruptive closing/reopening of separate windows.
- **BYOK (Bring Your Own Key)**: Direct client-side streaming to OpenAI, Anthropic, Google Gemini, OpenRouter, Groq, Ollama (100% local, no key required), or any custom OpenAI-compatible endpoint.
- **Dynamic Model Picker**: Automatically queries the provider's `/v1/models` endpoint so you never have hardcoded model lists. Safety guardrails filter out non-chat classifier models.
- **Rich Markdown & Code**: Full GFM support with formatted tables, syntax-highlighted code blocks, copy-to-clipboard buttons, and JetBrains Mono typography.
- **Customizable Appearance**: Position at Bottom-Center, Bottom-Right, or Bottom-Left. Smooth 0–100% background opacity control.

---

## 🎮 Usage

Summon Screen AI at any time using your configured shortcut (default: `Super+Shift+S`):

```bash
screen-ai --toggle
```

- **Type your question** and press `Enter`. Your screen is captured and transmitted along with your prompt.
- **Follow up** with additional questions directly in the thread.
- **Open Settings** by clicking the gear icon or running `screen-ai --settings`.
- **Dismiss** instantly with `Esc`.

---

## 🛠 Manual Build & Development

If you prefer building from source:

```bash
# Clone repository
git clone https://github.com/bhavyam2468/screen-ai.git
cd screen-ai

# Install dependencies & run development server
npm install
npm run tauri dev

# Build production binary
npm run build
cd src-tauri && cargo build --release
```

The compiled binary will be placed at `src-tauri/target/release/screen-ai`.

---

## 🗑 Uninstallation

Screen AI comes with a dedicated uninstaller that cleanly removes binaries, desktop launchers, autostart entries, and compositor shortcut configs:

```bash
screen-ai-uninstall
```

To also delete saved API keys and configurations:

```bash
screen-ai-uninstall --purge
```

Or run via curl:

```bash
curl -fsSL https://raw.githubusercontent.com/bhavyam2468/screen-ai/main/uninstall.sh | bash
```

---

## 📄 License

MIT © [Screen AI Contributors](LICENSE)

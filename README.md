# Screen AI

**Ask an AI about what’s on your screen.** A small Linux overlay with screen capture, streaming answers, Markdown, and bring-your-own-key providers.

Screen AI uses GTK layer-shell when the current desktop supports it, with a regular-window fallback elsewhere. The installer has dedicated integration for Niri, Hyprland, Sway, i3, River, GNOME, Plasma, Cinnamon, MATE, and Xfce; other sessions can use the app’s built-in X11 shortcut or a manually configured compositor command.

[![Source checks](https://github.com/bhavyam2468/screen-ai/actions/workflows/continuous.yml/badge.svg)](https://github.com/bhavyam2468/screen-ai/actions/workflows/continuous.yml)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Wayland%20%7C%20X11-f59e0b?style=flat-square)](https://github.com/bhavyam2468/screen-ai)
[![Tauri](https://img.shields.io/badge/Tauri-v2-f97316?style=flat-square&logo=tauri&logoColor=white)](https://tauri.app)

---

## Install

Run the source installer from a terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/bhavyam2468/screen-ai/main/install.sh | bash
```

The repository intentionally distributes **source code only**. The installer downloads the source and compiles the frontend and native app on your computer; the first build can take several minutes. It can install common build/runtime dependencies through `apt`, `dnf`, `pacman`, `zypper`, `xbps`, or `apk`, and offers rustup if the distro Rust compiler is too old. You need Rust 1.78+, Node.js 18+, GTK/WebKitGTK development libraries, and an available screenshot backend.

Useful options:

```bash
# Accept prompts and install dependencies automatically
curl -fsSL https://raw.githubusercontent.com/bhavyam2468/screen-ai/main/install.sh | bash -s -- --yes

# Skip package-manager changes (the required toolchain must already be installed)
curl -fsSL https://raw.githubusercontent.com/bhavyam2468/screen-ai/main/install.sh | bash -s -- --no-deps

# Install without compositor shortcut/autostart changes
curl -fsSL https://raw.githubusercontent.com/bhavyam2468/screen-ai/main/install.sh | bash -s -- --no-bind
```

When running from a cloned checkout, `bash ./install.sh` or `bash ./setup.sh` fast-forwards its tracking branch (`git pull --ff-only`) and builds that checkout. Local changes or divergent history are not overwritten. The interactive setup can configure a provider, model, overlay position, and opacity. Settings and API keys stay in your XDG config directory and are not removed unless you pass `--purge` to the uninstaller.

### Desktop and compositor integration

- **Niri:** the installer uses a managed top-level KDL include, validates it, and adds the shortcut and startup entry together. Includes require Niri 25.11 or newer; older versions are left untouched and receive manual instructions.
- **Hyprland:** current Lua configs get a managed Lua sidecar using `hl.bind()` and the `hyprland.start` event. Legacy `.conf` configs get a hyprlang sidecar only when that is the active format. On Hyprland 0.55+, a stale `.conf` is not edited as a substitute for Lua.
- **Sway/i3/River:** startup and shortcut setup use one managed integration per session. The installer avoids extra window rules for the layer-shell overlay.
- **Plasma:** shortcut registration is version-sensitive. The installer avoids an occupied shortcut and leaves a clear System Settings fallback when it cannot safely register one.
- **GNOME, Cinnamon, MATE, and Xfce:** shortcuts use their desktop settings and the tray uses one XDG autostart entry.

Config files reached through symlinks or paths the installer cannot safely edit are left alone. Managed drop-ins have a marker, existing configs receive a first-install `.screen-ai-bak` backup, and unsupported configurations get manual instructions instead of speculative edits. GTK layer-shell is not available in every desktop/session (notably GNOME Wayland and X11); Screen AI keeps a normal-window fallback for those environments.

---

## Use

Open Screen AI with your configured shortcut (default `Super+Shift+S`) or:

```bash
screen-ai --toggle
```

- Ask a question and press **Enter**. Your screenshot is sent with the prompt to the provider you configured; **Shift+Enter** adds a line.
- Click the screenshot thumbnail for a crosshair snip. Drag over the screen to replace the full-screen image with just that region; press **Esc** to cancel.
- Type **`/`** to browse commands, or press **Ctrl+K** to open the command palette. Use **↑ / ↓**, **Enter**, and **Tab** without leaving the input bar. Useful commands include `/model`, `/provider openai`, `/key gemini <key>`, `/theme qt`, `/update`, `/capture`, `/hide`, and `/exit` (quit the tray app).
- Type **`@`** to find and mention a local file. Mentioned files are read-only UTF-8 text, limited to 512 KiB per file and 1 MiB total per request, and are sent to the selected provider as context. Binary files are not attached.
- Settings are split into **Model**, **Appearance**, and **Updates** subpanels. Gemini, OpenAI, Anthropic, OpenRouter, Groq, Ollama, and custom provider profiles each keep their own API key, endpoint, and model selection.
- Continue with follow-up questions in the same thread. Open settings with the gear button or `screen-ai --settings`; `Ctrl+,` toggles the settings panel.
- Dismiss the overlay with **Esc**.

Settings can follow the desktop theme or use a detected **Qt / Matugen** palette. Screen AI reads KDE colors from `~/.config/kdeglobals` and active `qt5ct` / `qt6ct` color-scheme files, then maps window, surface, text, button, selection/accent, and link colors into the overlay. If Matugen writes to one of those active Qt/KDE theme files, its colors are picked up at launch or the next time the overlay is summoned. Matugen templates can write anywhere, so other custom output paths are not guessed. Screen AI is a Tauri WebView rather than a Qt widget app: Qt widget styles, control geometry, and Qt fonts cannot be imported directly; its layout, motion, and Geist typography stay Screen AI's own.

Providers include Gemini, OpenAI, Anthropic, OpenRouter, Groq, Ollama, and custom OpenAI-compatible endpoints. Add your own provider key; no hosted Screen AI key is required. The interface uses self-hosted Geist and Geist Mono variable fonts (Fontsource), so it does not fetch typography from a third-party CDN; see [`licenses/GEIST-OFL-1.1.txt`](licenses/GEIST-OFL-1.1.txt).

---

## Updating

Installation and updating use the same setup script. Run it again to pull and install the latest source:

```bash
bash ./setup.sh
# Or, from anywhere after installing:
screen-ai-update
# Check only (git fetch; no build or checkout changes):
screen-ai-update --check
```

The Settings **Pull & build update** button is just a wrapper around setup. Checks use `git fetch origin main`, comparing the fetched commit with the running binary's embedded revision. Updates use `git pull --ff-only`, install JavaScript dependencies, build locally, and atomically replace the executable. The existing checkout and Cargo build cache are reused instead of downloading a fresh source tree each time. Remote installs retain their checkout in `${XDG_DATA_HOME:-~/.local/share}/screen-ai/source`; clone-based installs reuse that clone and its tracking branch. Keep that clone available for subsequent updates.

Existing provider settings are kept. The app button skips provider/compositor setup and launching so the running app remains open; restart it after success. Only one setup/check runs at a time, and local changes or divergent history cause setup to stop rather than overwrite work.

To try a review before it merges, use **Build a pull request** with a managed-checkout install. This invokes the same setup script with the PR's commit, not a second updater. Only build PRs you trust: building source executes its scripts. The next normal update returns the managed checkout to `main`. No prebuilt executable is downloaded.

---

## Build and develop manually

From a clone, install the JavaScript dependencies and use the Tauri development command:

```bash
npm ci
npm run tauri dev
```

A manual release build (for your own machine) is:

```bash
npm run build
cargo build --locked --release --manifest-path src-tauri/Cargo.toml
```

The executable is written to `src-tauri/target/release/screen-ai`. GitHub Actions run source/lockfile checks only; they do not compile or publish app binaries. Geist typography is self-hosted from the Fontsource packages and covered by the included SIL Open Font License notice.

---

## Uninstall

```bash
screen-ai-uninstall
```

This removes the app, updater, managed desktop entries, and marked compositor integration while keeping settings and first-install config backups. To also delete saved provider keys and preferences:

```bash
screen-ai-uninstall --purge
```

---

## License

MIT — see [LICENSE](LICENSE).

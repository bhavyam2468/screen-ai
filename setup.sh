#!/usr/bin/env bash
# Screen AI Overlay — one-shot setup for Linux (X11 + Wayland).
# Installs missing dependencies, builds the app, installs it to ~/.local/bin.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_OUT="$HOME/.local/bin/screen-ai"
DESKTOP_FILE="$HOME/.local/share/applications/screen-ai.desktop"

info()  { printf '\033[1;36m› %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m! %s\033[0m\n' "$*"; }
fail()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ── distro detection ──────────────────────────────────────────────
DISTRO_ID="unknown"
DISTRO_LIKE=""
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_ID="${ID:-unknown}"
  DISTRO_LIKE="${ID_LIKE:-}"
fi
info "Detected distro: $DISTRO_ID (like: ${DISTRO_LIKE:-—})"

install_pkgs() {
  # $1 = manager name for display, rest handled per-branch
  if have apt-get; then
    info "Installing system packages (apt)…"
    sudo apt-get update -y
    sudo apt-get install -y \
      build-essential curl wget file pkg-config \
      libssl-dev \
      libwebkit2gtk-4.1-dev libgtk-3-dev \
      libayatana-appindicator3-dev librsvg2-dev libxdo-dev \
      libpipewire-0.3-dev pipewire \
      xdg-desktop-portal xdg-desktop-portal-gtk \
      grim slurp gnome-screenshot spectacle scrot maim || {
        warn "Some optional screenshot tools failed — continuing (at least one backend is enough)."
      }
  elif have dnf; then
    info "Installing system packages (dnf)…"
    sudo dnf install -y \
      gcc-c++ curl wget file pkg-config openssl-devel \
      webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel librsvg2-devel libXdo-devel \
      pipewire-devel pipewire \
      xdg-desktop-portal xdg-desktop-portal-gtk \
      grim slurp gnome-screenshot spectacle scrot maim || {
        warn "Some optional screenshot tools failed — continuing."
      }
  elif have pacman; then
    info "Installing system packages (pacman)…"
    sudo pacman -Sy --needed --noconfirm \
      base-devel curl wget file pkgconf openssl \
      webkit2gtk-4.1 gtk3 libayatana-appindicator librsvg libxdo \
      pipewire libpipewire \
      xdg-desktop-portal xdg-desktop-portal-gtk \
      grim slurp gnome-screenshot spectacle scrot maim || {
        warn "Some optional screenshot tools failed — continuing."
      }
  elif have zypper; then
    info "Installing system packages (zypper)…"
    sudo zypper install -y \
      gcc-c++ curl wget file pkg-config libopenssl-devel \
      webkit2gtk3-devel gtk3-devel libayatana-appindicator3-devel librsvg-devel \
      pipewire-devel \
      xdg-desktop-portal xdg-desktop-portal-gtk \
      grim slurp gnome-screenshot spectacle scrot maim || {
        warn "Some optional screenshot tools failed — continuing."
      }
  else
    fail "No supported package manager (apt/dnf/pacman/zypper). Install manually: Rust, Node 18+, webkit2gtk-4.1 dev libs, a screenshot tool (grim/gnome-screenshot/spectacle/scrot/maim) — then re-run."
  fi
}

# ── system deps ───────────────────────────────────────────────────
NEED_SYS=false
for b in pkg-config curl file; do have "$b" || NEED_SYS=true; done
pkg-config --exists webkit2gtk-4.1 2>/dev/null || NEED_SYS=true
if [[ "$NEED_SYS" == true ]]; then
  install_pkgs
else
  info "Core system libraries already present — checking screenshot tools…"
  if ! have grim && ! have gnome-screenshot && ! have spectacle && ! have scrot && ! have maim && ! have import; then
    warn "No screenshot CLI found — installing fallbacks…"
    install_pkgs
  else
    ok "Screenshot backend available."
  fi
fi

# ── rust ──────────────────────────────────────────────────────────
if have cargo && have rustc; then
  ok "Rust present: $(rustc --version)"
else
  info "Installing Rust (rustup)…"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
fi
export PATH="$HOME/.cargo/bin:$PATH"
ok "Rust: $(rustc --version)"

# ── node ──────────────────────────────────────────────────────────
node_ok=false
if have node; then
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [[ "$NODE_MAJOR" -ge 18 ]]; then node_ok=true; fi
fi
if [[ "$node_ok" == true ]]; then
  ok "Node present: $(node --version)"
else
  info "Installing Node.js…"
  if have apt-get; then
    sudo apt-get install -y nodejs npm || true
  elif have dnf; then
    sudo dnf install -y nodejs npm || true
  elif have pacman; then
    sudo pacman -Sy --needed --noconfirm nodejs npm || true
  elif have zypper; then
    sudo zypper install -y nodejs npm || true
  fi
  if ! have node || [[ "$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)" -lt 18 ]]; then
    fail "Node 18+ is required but couldn't be installed automatically. Install it (https://nodejs.org) and re-run setup.sh."
  fi
  ok "Node: $(node --version)"
fi

# ── build ─────────────────────────────────────────────────────────
info "Installing frontend dependencies…"
cd "$APP_DIR"
npm install

info "Building frontend…"
npm run build

info "Building native binary (release — takes a few minutes)…"
# cargo build directly: tauri-build embeds the already-built ../dist web UI.
(cd src-tauri && cargo build --release)

BIN_BUILT="$APP_DIR/src-tauri/target/release/screen-ai"
[[ -x "$BIN_BUILT" ]] || fail "Build finished but binary not found at $BIN_BUILT"

# ── install ───────────────────────────────────────────────────────
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
cp -f "$BIN_BUILT" "$BIN_OUT"
chmod +x "$BIN_OUT"
ok "Installed → $BIN_OUT"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI
Comment=Ask AI about your screen
Exec=$BIN_OUT
Icon=dialog-question
Terminal=false
Categories=Utility;
StartupWMClass=Screen AI
EOF
ok "Desktop entry → $DESKTOP_FILE"
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) warn "\$HOME/.local/bin is not on your PATH — add it:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# ── keybind recipe ────────────────────────────────────────────────
SESSION="${XDG_SESSION_TYPE:-unknown} (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-?})"
echo ""
ok "Done! Session: $SESSION"
echo ""
echo "┌─ Global shortcut ─────────────────────────────────────────────"
echo "│ Wayland (Niri / GNOME / KDE / Hyprland / Sway): bind a key to run:"
echo "│     $BIN_OUT --toggle"
echo "│"
echo "│   Niri (~/.config/niri/config.kdl):"
echo "│     Mod+Shift+S { spawn \"screen-ai\" \"--toggle\"; }"
echo "│   GNOME:   Settings → Keyboard → View & Customize → Custom → +"
echo "│   KDE:     Settings → Shortcuts → Add New → Command/URL"
echo "│   Hyprland (~/.config/hypr/hyprland.conf):"
echo "│     bind = SUPER SHIFT, S, exec, $BIN_OUT --toggle"
echo "│   Sway (~/.config/sway/config):"
echo "│     bindsym Mod4+Shift+s exec $BIN_OUT --toggle"
echo "│"
echo "│ X11: Super+Shift+S or Ctrl+Alt+Space works in-app (no setup needed)."
echo "│ Autostart: add Screen AI to your autostart / compositor exec-once."
echo "└───────────────────────────────────────────────────────────────"
echo ""
echo "Launch now:  $BIN_OUT"
echo "First launch opens settings — paste your API key, pick a model + corner, Save."

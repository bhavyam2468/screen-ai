#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Screen AI — uninstaller
# ─────────────────────────────────────────────────────────────────────────────
set -u

BIN_DIR="${SCREEN_AI_BIN_DIR:-$HOME/.local/bin}"
SHARE_DIR="$HOME/.local/share/screen-ai"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/screen-ai"
PURGE=0
ASSUME_YES=0

for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help)
      echo "Usage: screen-ai-uninstall [--purge] [--yes]"
      echo "  --purge   Also delete configuration and saved API keys ($CFG_DIR)"
      echo "  --yes, -y Skip confirmation prompts"
      exit 0
      ;;
  esac
done

HAS_TTY=0; [ -r /dev/tty ] && [ -w /dev/tty ] && HAS_TTY=1
TRUE=0; case "${COLORTERM:-}" in truecolor|24bit) TRUE=1 ;; esac
[ -t 1 ] || TRUE=0
RST=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
if [ -t 1 ]; then
  RED=$'\e[38;2;244;63;94m'; GRN=$'\e[38;2;74;222;128m'; AMB=$'\e[38;2;251;191;36m'; CYN=$'\e[38;2;0;210;255m'
else
  RED=''; GRN=''; AMB=''; CYN=''; RST=''; BOLD=''; DIM=''
fi

STOPS=("0 198 255" "0 114 255" "155 81 224" "255 0 127")

gradient() {
  local text="$1" n i seg t idx r g b out="" ch
  if [ "$TRUE" -ne 1 ]; then printf '%s' "$text"; return; fi
  n=${#text}; [ "$n" -le 1 ] && n=2
  for ((i = 0; i < ${#text}; i++)); do
    ch="${text:i:1}"
    if [ "$ch" = " " ]; then out+=" "; continue; fi
    t=$((i * 1000 / (n - 1)))
    seg=$((t * (${#STOPS[@]} - 1)))
    idx=$((seg / 1000)); [ "$idx" -ge $((${#STOPS[@]} - 1)) ] && idx=$((${#STOPS[@]} - 2))
    local f=$((seg - idx * 1000))
    read -r r1 g1 b1 <<<"${STOPS[idx]}"; read -r r2 g2 b2 <<<"${STOPS[idx + 1]}"
    r=$((r1 + (r2 - r1) * f / 1000)); g=$((g1 + (g2 - g1) * f / 1000)); b=$((b1 + (b2 - b1) * f / 1000))
    out+=$'\e[38;2;'"$r;$g;${b}m$ch"
  done
  printf '%s%s' "$out" "$RST"
}

ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '  %s!%s %s\n' "$AMB" "$RST" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; }
note() { printf '    %s%s%s\n' "$DIM" "$1" "$RST"; }
step() { printf '\n  %s%s%s\n' "$BOLD" "$(gradient "▌ $1")" "$RST"; }

confirm() {
  local q="$1" def="${2:-y}" ans
  if [ "$HAS_TTY" -eq 0 ] || [ "$ASSUME_YES" -eq 1 ]; then [ "$def" = y ]; return; fi
  printf '  %s?%s %s %s[%s]%s ' "$CYN" "$RST" "$q" "$DIM" "$([ "$def" = y ] && echo Y/n || echo y/N)" "$RST" >/dev/tty
  read -r ans </dev/tty || ans=""
  ans="${ans:-$def}"; case "$ans" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

printf '\n  %s\n' "$(gradient "Screen AI — Uninstall")"

if ! confirm "Uninstall Screen AI from this system?" y; then
  echo "Aborted."
  exit 0
fi

step "Terminating active processes"
if pgrep -x screen-ai >/dev/null 2>&1; then
  pkill -x screen-ai 2>/dev/null || true
  sleep 0.5
  ok "stopped running instances"
else
  note "no active process found"
fi

step "Removing binaries and application assets"
rm -f "$BIN_DIR/screen-ai" "$BIN_DIR/screen-ai-uninstall"
rm -rf "$SHARE_DIR"
rm -f "$HOME/.local/share/applications/screen-ai.desktop"
rm -f "$HOME/.local/share/applications/screen-ai-settings.desktop"
rm -f "$HOME/.local/share/applications/screen-ai-toggle.desktop"
rm -f "$HOME/.config/autostart/screen-ai.desktop"
ok "removed binaries & desktop entries"

step "Cleaning compositor shortcuts & autostart"

# Niri
if [ -f "$HOME/.config/niri/config.kdl" ]; then
  sed -i '/screen-ai/d' "$HOME/.config/niri/config.kdl" 2>/dev/null || true
  rm -f "$HOME/.config/niri/screen-ai.kdl"
  ok "niri config cleaned"
fi

# Hyprland
if [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
  sed -i '/screen-ai/d' "$HOME/.config/hypr/hyprland.conf" 2>/dev/null || true
  rm -f "$HOME/.config/hypr/screen-ai.conf"
  if command -v hyprctl >/dev/null 2>&1; then hyprctl reload >/dev/null 2>&1 || true; fi
  ok "hyprland config cleaned"
fi

# Sway
if [ -f "$HOME/.config/sway/config" ]; then
  sed -i '/screen-ai/d' "$HOME/.config/sway/config" 2>/dev/null || true
  rm -f "$HOME/.config/sway/screen-ai.conf"
  if command -v swaymsg >/dev/null 2>&1; then swaymsg reload >/dev/null 2>&1 || true; fi
  ok "sway config cleaned"
fi

# i3
for f in "$HOME/.config/i3/config" "$HOME/.i3/config"; do
  if [ -f "$f" ]; then
    sed -i '/# screen-ai BEGIN/,/# screen-ai END/d' "$f" 2>/dev/null || true
    if command -v i3-msg >/dev/null 2>&1; then i3-msg reload >/dev/null 2>&1 || true; fi
    ok "i3 config cleaned"
    break
  fi
done

# GNOME
if command -v gsettings >/dev/null 2>&1; then
  cur=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "")
  if [[ "$cur" == *screen-ai* ]]; then
    new=$(echo "$cur" | sed "s/'\/org\/gnome\/settings-daemon\/plugins\/media-keys\/custom-keybindings\/screen-ai\/'//g" | sed 's/, *,/,/g; s/\[ *,/\[/; s/, *\]/\]/')
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new" 2>/dev/null || true
    gsettings reset-recursively org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/screen-ai/ 2>/dev/null || true
    ok "gnome shortcut reset"
  fi
fi

# Plasma
kw=""
command -v kwriteconfig6 >/dev/null 2>&1 && kw=kwriteconfig6
[ -z "$kw" ] && command -v kwriteconfig5 >/dev/null 2>&1 && kw=kwriteconfig5
if [ -n "$kw" ]; then
  $kw --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _launch --delete 2>/dev/null || true
fi

step "Configuration files"
if [ "$PURGE" -eq 1 ] || confirm "Delete configuration & API keys in $CFG_DIR?" n; then
  rm -rf "$CFG_DIR"
  ok "removed $CFG_DIR"
else
  note "kept $CFG_DIR (your API keys and preferences are preserved)"
fi

printf '\n  %s\n\n' "$(gradient "Screen AI uninstalled successfully.")"

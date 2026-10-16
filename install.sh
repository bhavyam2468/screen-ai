#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Screen AI — installer
#  curl -fsSL https://raw.githubusercontent.com/bhavyam2468/screen-ai/main/install.sh | bash
#
#  Flags:  --yes  --from-source  --no-deps  --no-bind  --no-setup  --help
# ─────────────────────────────────────────────────────────────────────────────
set -u
REPO="bhavyam2468/screen-ai"
BIN_DIR="${SCREEN_AI_BIN_DIR:-$HOME/.local/bin}"
SHARE_DIR="$HOME/.local/share/screen-ai"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/screen-ai"
LOG="$(mktemp -t screen-ai-install.XXXXXX.log)"

ASSUME_YES=0; FROM_SOURCE=0; NO_DEPS=0; NO_BIND=0; NO_SETUP=0
for a in "$@"; do
  case "$a" in
    -y|--yes) ASSUME_YES=1 ;;
    --from-source) FROM_SOURCE=1 ;;
    --no-deps) NO_DEPS=1 ;;
    --no-bind) NO_BIND=1 ;;
    --no-setup) NO_SETUP=1 ;;
    -h|--help) sed -n '2,9p' "$0" 2>/dev/null; exit 0 ;;
  esac
done

case "${LC_ALL:-${LANG:-}}" in *UTF-8*|*utf8*|*UTF8*) ;; *) export LC_ALL=C.UTF-8 ;; esac

# ── terminal / colour ────────────────────────────────────────────────────────
HAS_TTY=0; [ -r /dev/tty ] && [ -w /dev/tty ] && HAS_TTY=1
TRUE=0; case "${COLORTERM:-}" in truecolor|24bit) TRUE=1 ;; esac
[ -t 1 ] || TRUE=0
RST=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
if [ -t 1 ]; then RED=$'\e[38;2;244;63;94m'; GRN=$'\e[38;2;74;222;128m'; AMB=$'\e[38;2;251;191;36m'; CYN=$'\e[38;2;0;210;255m'
else RED=''; GRN=''; AMB=''; CYN=''; RST=''; BOLD=''; DIM=''; fi

STOPS=("0 198 255" "0 114 255" "155 81 224" "255 0 127")

# gradient <text>  — paints one line left→right across the stops
gradient() {
  local text="$1" n i seg t idx r g b out="" ch
  if [ "$TRUE" -ne 1 ]; then printf '%s' "$text"; return; fi
  n=${#text}; [ "$n" -le 1 ] && n=2
  for ((i = 0; i < ${#text}; i++)); do
    ch="${text:i:1}"
    if [ "$ch" = " " ]; then out+=" "; continue; fi
    t=$((i * 1000 / (n - 1)))                    # 0..1000
    seg=$((t * (${#STOPS[@]} - 1)))              # scaled by 1000
    idx=$((seg / 1000)); [ "$idx" -ge $((${#STOPS[@]} - 1)) ] && idx=$((${#STOPS[@]} - 2))
    local f=$((seg - idx * 1000))
    read -r r1 g1 b1 <<<"${STOPS[idx]}"; read -r r2 g2 b2 <<<"${STOPS[idx + 1]}"
    r=$((r1 + (r2 - r1) * f / 1000)); g=$((g1 + (g2 - g1) * f / 1000)); b=$((b1 + (b2 - b1) * f / 1000))
    out+=$'\e[38;2;'"$r;$g;${b}m$ch"
  done
  printf '%s%s' "$out" "$RST"
}

# gradient_block — same phase on every line (reads stdin)
gradient_block() {
  local lines=() line w=0
  while IFS= read -r line; do lines+=("$line"); [ ${#line} -gt $w ] && w=${#line}; done
  for line in "${lines[@]}"; do
    while [ ${#line} -lt $w ]; do line+=" "; done
    gradient "$line"; printf '\n'
  done
}

banner() {
  printf '\n'
  gradient_block <<'ART'
███████╗ ██████╗██████╗ ███████╗███████╗███╗   ██╗    █████╗ ██╗
██╔════╝██╔════╝██╔══██╗██╔════╝██╔════╝████╗  ██║   ██╔══██╗██║
███████╗██║     ██████╔╝█████╗  █████╗  ██╔██╗ ██║   ███████║██║
╚════██║██║     ██╔══██╗██╔══╝  ██╔══╝  ██║╚██╗██║   ██╔══██║██║
███████║╚██████╗██║  ██║███████╗███████╗██║ ╚████║   ██║  ██║██║
╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝  ╚═╝╚═╝
ART
  printf '\n  '; gradient "ask any AI about whatever is on your screen · bring your own key"; printf '\n  '
  gradient "niri · hyprland · sway · plasma · gnome · x11 · every compositor"; printf '\n\n'
}

rule() { printf '  '; gradient "$(printf '─%.0s' $(seq 1 66))"; printf '\n'; }
step() { printf '\n  %s%s%s\n' "$BOLD" "$(gradient "▌ $1")" "$RST"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '  %s!%s %s\n' "$AMB" "$RST" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; }
note() { printf '    %s%s%s\n' "$DIM" "$1" "$RST"; }
die()  { bad "$1"; [ -s "$LOG" ] && note "log: $LOG"; exit 1; }

# spin "message" cmd args…   — runs quietly with a braille spinner
spin() {
  local msg="$1"; shift
  "$@" >>"$LOG" 2>&1 &
  local pid=$! i=0 fr=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do printf '\r  %s%s%s %s' "$CYN" "${fr[i % 10]}" "$RST" "$msg"; i=$((i + 1)); sleep 0.08; done
    printf '\r\e[K'
  fi
  wait "$pid"; local rc=$?
  if [ $rc -eq 0 ]; then ok "$msg"; else bad "$msg"; tail -n 12 "$LOG" | sed 's/^/      /'; fi
  return $rc
}

ask_tty() { [ "$HAS_TTY" -eq 1 ] && [ "$ASSUME_YES" -eq 0 ]; }

# confirm "question" default(y|n)
confirm() {
  local q="$1" def="${2:-y}" ans
  if ! ask_tty; then [ "$def" = y ]; return; fi
  printf '  %s?%s %s %s[%s]%s ' "$CYN" "$RST" "$q" "$DIM" "$([ "$def" = y ] && echo Y/n || echo y/N)" "$RST" >/dev/tty
  read -r ans </dev/tty || ans=""
  ans="${ans:-$def}"; case "$ans" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

# prompt "question" "default"  → $REPLY_TXT
prompt() {
  REPLY_TXT="$2"
  ask_tty || return 0
  printf '  %s?%s %s %s(%s)%s ' "$CYN" "$RST" "$1" "$DIM" "$2" "$RST" >/dev/tty
  local a; read -r a </dev/tty || a=""; REPLY_TXT="${a:-$2}"
}

prompt_secret() {
  REPLY_TXT=""
  ask_tty || return 0
  printf '  %s?%s %s %s(hidden, enter to skip)%s ' "$CYN" "$RST" "$1" "$DIM" "$RST" >/dev/tty
  local a; read -rs a </dev/tty || a=""; printf '\n' >/dev/tty; REPLY_TXT="$a"
}

# choose "title" opt… → $CHOICE (index)   ↑/↓ + enter, gradient highlight
choose() {
  local title="$1"; shift
  local opts=("$@") n=$# sel=0 key rest i
  CHOICE=0
  ask_tty || return 0
  printf '  %s?%s %s %s(↑/↓ enter)%s\n' "$CYN" "$RST" "$title" "$DIM" "$RST" >/dev/tty
  printf '\e[?25l' >/dev/tty
  trap 'printf "\e[?25h" >/dev/tty' RETURN
  draw() {
    for ((i = 0; i < n; i++)); do
      if [ $i -eq $sel ]; then printf '\r\e[K    %s %s\n' "$(gradient '❯')" "$(gradient "${opts[i]}")" >/dev/tty
      else printf '\r\e[K      %s%s%s\n' "$DIM" "${opts[i]}" "$RST" >/dev/tty; fi
    done
  }
  draw
  while true; do
    IFS= read -rsn1 key </dev/tty || break
    if [ "$key" = $'\e' ]; then
      read -rsn2 -t 0.05 rest </dev/tty || rest=""
      case "$rest" in '[A') sel=$(((sel + n - 1) % n)) ;; '[B') sel=$(((sel + 1) % n)) ;; esac
    elif [ -z "$key" ]; then break
    elif [ "$key" = k ]; then sel=$(((sel + n - 1) % n))
    elif [ "$key" = j ]; then sel=$(((sel + 1) % n)); fi
    printf '\e[%dA' "$n" >/dev/tty; draw
  done
  CHOICE=$sel
}

have() { command -v "$1" >/dev/null 2>&1; }
SUDO=""; [ "$(id -u)" -ne 0 ] && have sudo && SUDO="sudo"

# ── environment detection ────────────────────────────────────────────────────
detect_env() {
  . /etc/os-release 2>/dev/null || true
  DISTRO_ID="${ID:-unknown}"; DISTRO_LIKE="${ID_LIKE:-}"; DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"
  PM=""
  for fam in $DISTRO_ID $DISTRO_LIKE; do
    case "$fam" in
      arch|manjaro|endeavouros|cachyos|garuda) PM=pacman; break ;;
      debian|ubuntu|linuxmint|pop|neon|elementary|zorin|kali) PM=apt; break ;;
      fedora|rhel|centos|nobara|bazzite) PM=dnf; break ;;
      opensuse*|suse|sles) PM=zypper; break ;;
      void) PM=xbps; break ;;
      alpine) PM=apk; break ;;
    esac
  done
  [ -z "$PM" ] && for p in pacman apt-get dnf zypper xbps-install apk; do have "$p" && { PM="${p%-get}"; PM="${PM%-install}"; break; }; done

  SESSION="${XDG_SESSION_TYPE:-}"
  [ -z "$SESSION" ] && { [ -n "${WAYLAND_DISPLAY:-}" ] && SESSION=wayland || SESSION=x11; }

  DE="$(echo "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}" | tr 'A-Z' 'a-z')"
  WM="other"
  if   [ -n "${NIRI_SOCKET:-}" ] || [[ "$DE" == *niri* ]]; then WM=niri
  elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [[ "$DE" == *hypr* ]]; then WM=hyprland
  elif [ -n "${SWAYSOCK:-}" ] || [[ "$DE" == *sway* ]]; then WM=sway
  elif [[ "$DE" == *kde* || "$DE" == *plasma* ]]; then WM=plasma
  elif [[ "$DE" == *gnome* || "$DE" == *unity* || "$DE" == *budgie* ]]; then WM=gnome
  elif [[ "$DE" == *xfce* ]]; then WM=xfce
  elif [[ "$DE" == *cinnamon* ]]; then WM=cinnamon
  elif [[ "$DE" == *mate* ]]; then WM=mate
  elif [ -n "${I3SOCK:-}" ] || [[ "$DE" == *i3* ]]; then WM=i3
  elif [[ "$DE" == *river* || "$DE" == *labwc* || "$DE" == *wayfire* ]]; then WM=wlroots
  fi
  ARCH="$(uname -m)"
}

# ── dependencies ─────────────────────────────────────────────────────────────
runtime_pkgs() {
  local shot
  [ "$SESSION" = wayland ] && shot=grim || shot=maim
  case "$PM" in
    pacman) echo "webkit2gtk-4.1 gtk3 gtk-layer-shell libayatana-appindicator $shot curl" ;;
    apt)    echo "libwebkit2gtk-4.1-0 libgtk-3-0 libgtk-layer-shell0 libayatana-appindicator3-1 $shot curl" ;;
    dnf)    echo "webkit2gtk4.1 gtk3 gtk-layer-shell libayatana-appindicator-gtk3 $shot curl" ;;
    zypper) echo "libwebkit2gtk-4_1-0 gtk3 libgtk-layer-shell0 libayatana-appindicator3-1 $shot curl" ;;
    xbps)   echo "webkit2gtk gtk+3 gtk-layer-shell libayatana-appindicator $shot curl" ;;
    apk)    echo "webkit2gtk-4.1 gtk+3.0 gtk-layer-shell libayatana-appindicator $shot curl" ;;
  esac
}

build_pkgs() {
  case "$PM" in
    pacman) echo "base-devel git nodejs npm rust webkit2gtk-4.1 gtk3 gtk-layer-shell libayatana-appindicator openssl pkgconf" ;;
    apt)    echo "build-essential git pkg-config nodejs npm libwebkit2gtk-4.1-dev libgtk-3-dev libgtk-layer-shell-dev libayatana-appindicator3-dev libssl-dev" ;;
    dnf)    echo "gcc gcc-c++ git pkgconf-pkg-config nodejs npm rust cargo webkit2gtk4.1-devel gtk3-devel gtk-layer-shell-devel libayatana-appindicator-gtk3-devel openssl-devel" ;;
    zypper) echo "gcc gcc-c++ git pkg-config nodejs npm rust cargo webkit2gtk4_1-devel gtk3-devel gtk-layer-shell-devel libayatana-appindicator3-devel libopenssl-devel" ;;
    xbps)   echo "base-devel git nodejs rust cargo webkit2gtk-devel gtk+3-devel gtk-layer-shell-devel libayatana-appindicator-devel openssl-devel pkg-config" ;;
    apk)    echo "build-base git nodejs npm rust cargo webkit2gtk-4.1-dev gtk+3.0-dev gtk-layer-shell-dev libayatana-appindicator-dev openssl-dev pkgconf" ;;
  esac
}

pm_install() {
  case "$PM" in
    pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
    apt)    $SUDO apt-get update -y && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    zypper) $SUDO zypper --non-interactive install "$@" ;;
    xbps)   $SUDO xbps-install -Sy "$@" ;;
    apk)    $SUDO apk add "$@" ;;
    *)      return 1 ;;
  esac
}

install_deps() {
  local pkgs="$1"
  [ -z "$PM" ] && { warn "unknown package manager — install these yourself: GTK3, WebKitGTK 4.1, gtk-layer-shell, grim/maim"; return 0; }
  if [ -n "$SUDO" ] || [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC2086
    spin "installing packages ($PM): $pkgs" pm_install $pkgs || warn "some packages failed — continuing; the app may be missing libraries"
  else
    warn "no sudo — please install: $pkgs"
  fi
}

# ── obtaining the binary ─────────────────────────────────────────────────────
bin_ok() {
  [ -x "$1" ] || return 1
  have ldd || return 0
  ! ldd "$1" 2>/dev/null | grep -q "not found"
}

download_release() {
  [ "$ARCH" = x86_64 ] || return 1
  have curl || return 1
  local url="https://github.com/$REPO/releases/latest/download/screen-ai-x86_64-linux.tar.gz" tmp
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/sa.tgz" && tar -xzf "$tmp/sa.tgz" -C "$tmp" && [ -f "$tmp/screen-ai" ] || { rm -rf "$tmp"; return 1; }
  mkdir -p "$BIN_DIR" && install -m755 "$tmp/screen-ai" "$BIN_DIR/screen-ai.new" && mv -f "$BIN_DIR/screen-ai.new" "$BIN_DIR/screen-ai"
  rm -rf "$tmp"
}

build_from_source() {
  have git || return 1
  local src="${XDG_CACHE_HOME:-$HOME/.cache}/screen-ai-src"
  rm -rf "$src"
  git clone --depth 1 "https://github.com/$REPO.git" "$src" || return 1
  cd "$src" || return 1
  if ! have cargo; then
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal || return 1
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  npm install --no-audit --no-fund || return 1
  npm run build || return 1
  (cd src-tauri && cargo build --release) || return 1
  mkdir -p "$BIN_DIR" && install -m755 src-tauri/target/release/screen-ai "$BIN_DIR/screen-ai"
}

get_binary() {
  if [ "$FROM_SOURCE" -eq 0 ]; then
    if spin "downloading prebuilt binary" download_release && bin_ok "$BIN_DIR/screen-ai"; then return 0; fi
    warn "prebuilt binary unavailable or incompatible with this system — building from source"
  fi
  if [ "$NO_DEPS" -eq 0 ]; then
    confirm "Install build tools (rust, node, dev headers)?" y && install_deps "$(build_pkgs)"
  fi
  spin "building from source (a few minutes)" build_from_source || die "build failed"
  bin_ok "$BIN_DIR/screen-ai" || die "installed binary has unresolved libraries"
}

# ── provider setup (BYOK) ────────────────────────────────────────────────────
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

list_models() { # provider base key → one id per line
  local prov="$1" base="${2%/}" key="$3" raw
  case "$prov" in
    gemini)    raw=$(curl -fsSL --max-time 12 "$base/v1beta/models?key=$key" 2>/dev/null | grep -o '"name": *"models/[^"]*"' | sed 's/.*models\///; s/"//') ;;
    anthropic) raw=$(curl -fsSL --max-time 12 -H "x-api-key: $key" -H "anthropic-version: 2023-06-01" "$base/v1/models" 2>/dev/null | grep -o '"id": *"[^"]*"' | sed 's/.*: *"//; s/"//') ;;
    ollama)    raw=$(curl -fsSL --max-time 6 "$base/api/tags" 2>/dev/null | grep -o '"name": *"[^"]*"' | sed 's/.*: *"//; s/"//') ;;
    *)         raw=$(curl -fsSL --max-time 12 -H "Authorization: Bearer $key" "$base/models" 2>/dev/null | grep -o '"id": *"[^"]*"' | sed 's/.*: *"//; s/"//') ;;
  esac
  printf '%s\n' "$raw" | grep -vi 'guard\|moderat\|safety\|embed\|whisper\|tts\|dall' | sed '/^$/d'
}

setup_provider() {
  local labels=("Gemini" "OpenAI" "Anthropic" "OpenRouter" "Groq" "Ollama (local, no key)" "Custom OpenAI-compatible")
  local ids=(gemini openai anthropic openrouter groq ollama custom)
  local bases=("https://generativelanguage.googleapis.com" "https://api.openai.com/v1" "https://api.anthropic.com" "https://openrouter.ai/api/v1" "https://api.groq.com/openai/v1" "http://localhost:11434" "")
  local defm=("gemini-2.5-flash" "gpt-4o-mini" "claude-sonnet-4-5" "openrouter/auto" "meta-llama/llama-4-scout-17b-16e-instruct" "llava" "")

  choose "Which AI provider?" "${labels[@]}"
  local p=$CHOICE PROV="${ids[$CHOICE]}" BASE="${bases[$CHOICE]}" MODEL="${defm[$CHOICE]}" KEY=""
  [ "$PROV" = custom ] && { prompt "Base URL" "https://api.example.com/v1"; BASE="$REPLY_TXT"; }
  [ "$PROV" != ollama ] && { prompt_secret "API key"; KEY="$REPLY_TXT"; }

  if ask_tty && [ -n "$BASE" ] && { [ -n "$KEY" ] || [ "$PROV" = ollama ]; }; then
    local models=()
    note "fetching available models…"
    mapfile -t models < <(list_models "$PROV" "$BASE" "$KEY" | head -n 14)
    if [ ${#models[@]} -gt 0 ]; then
      ok "found ${#models[@]}+ models"
      choose "Pick a vision-capable model" "${models[@]}" "↳ type one manually"
      if [ "$CHOICE" -lt ${#models[@]} ]; then MODEL="${models[$CHOICE]}"
      else prompt "Model id" "$MODEL"; MODEL="$REPLY_TXT"; fi
    else
      warn "could not list models (bad key or offline) — enter one manually"
      prompt "Model id" "$MODEL"; MODEL="$REPLY_TXT"
    fi
  else
    prompt "Model id" "$MODEL"; MODEL="$REPLY_TXT"
  fi

  choose "Where should the overlay sit?" "Bottom center" "Bottom right" "Bottom left"
  local POS=(bottom-center bottom-right bottom-left); POSITION="${POS[$CHOICE]}"
  prompt "Background opacity 0-100" "100"; OPACITY="$REPLY_TXT"
  case "$OPACITY" in ''|*[!0-9]*) OPACITY=100 ;; esac; [ "$OPACITY" -gt 100 ] && OPACITY=100

  mkdir -p "$CFG_DIR"
  cat >"$CFG_DIR/settings.json" <<EOF
{
  "provider": "$PROV",
  "api_key": "$(json_escape "$KEY")",
  "base_url": "$(json_escape "$BASE")",
  "model": "$(json_escape "$MODEL")",
  "position": "$POSITION",
  "max_tokens": 800,
  "bg_opacity": $OPACITY
}
EOF
  chmod 600 "$CFG_DIR/settings.json"
  ok "saved $CFG_DIR/settings.json"
}

# ── keybinding + autostart per environment ───────────────────────────────────
MARK="# screen-ai"
add_line_once() { # file line
  mkdir -p "$(dirname "$1")"; touch "$1"
  grep -qxF "$2" "$1" || printf '%s\n' "$2" >>"$1"
}

bind_niri() {
  local cfg="$HOME/.config/niri/config.kdl" inc="$HOME/.config/niri/screen-ai.kdl"
  [ -f "$cfg" ] || { warn "no niri config found"; return 1; }
  cat >"$inc" <<EOF
$MARK — managed by the Screen AI installer; removed by the uninstaller
binds {
    $NIRI_KEY hotkey-overlay-title="Screen AI" { spawn "screen-ai" "--toggle"; }
}
spawn-at-startup "screen-ai"
EOF
  add_line_once "$cfg" "include \"screen-ai.kdl\" $MARK"
  have niri && niri validate >/dev/null 2>&1 || { warn "niri rejected the config — is your niri older than 25.11 (no 'include')?"; return 1; }
  ok "niri: $NIRI_KEY → screen-ai (hot-reloads automatically)"
}

bind_hyprland() {
  local cfg="$HOME/.config/hypr/hyprland.conf" inc="$HOME/.config/hypr/screen-ai.conf"
  [ -f "$cfg" ] || { warn "no hyprland.conf found"; return 1; }
  cat >"$inc" <<EOF
$MARK — managed by the Screen AI installer
bind = $HYPR_MODS, $HYPR_KEY, exec, screen-ai --toggle
exec-once = screen-ai
EOF
  add_line_once "$cfg" "source = ~/.config/hypr/screen-ai.conf $MARK"
  have hyprctl && hyprctl reload >/dev/null 2>&1
  ok "hyprland: $HYPR_MODS+$HYPR_KEY → screen-ai"
}

bind_sway() {
  local cfg="$HOME/.config/sway/config" inc="$HOME/.config/sway/screen-ai.conf"
  [ -f "$cfg" ] || { warn "no sway config found"; return 1; }
  cat >"$inc" <<EOF
$MARK — managed by the Screen AI installer
bindsym $SWAY_KEY exec screen-ai --toggle
exec screen-ai
EOF
  add_line_once "$cfg" "include ~/.config/sway/screen-ai.conf $MARK"
  have swaymsg && swaymsg reload >/dev/null 2>&1
  ok "sway: $SWAY_KEY → screen-ai"
}

bind_i3() {
  local cfg="$HOME/.config/i3/config"; [ -f "$cfg" ] || cfg="$HOME/.i3/config"
  [ -f "$cfg" ] || { warn "no i3 config found"; return 1; }
  grep -q "screen-ai BEGIN" "$cfg" || cat >>"$cfg" <<EOF

# screen-ai BEGIN
bindsym $SWAY_KEY exec --no-startup-id screen-ai --toggle
exec --no-startup-id screen-ai
# screen-ai END
EOF
  have i3-msg && i3-msg reload >/dev/null 2>&1
  ok "i3: $SWAY_KEY → screen-ai"
}

bind_gnome() {
  have gsettings || return 1
  local base=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/screen-ai/
  local schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$base"
  gsettings set "$schema" name "Screen AI"
  gsettings set "$schema" command "screen-ai --toggle"
  gsettings set "$schema" binding "$GNOME_KEY"
  local cur; cur="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)"
  case "$cur" in *"$base"*) ;; *)
    if [ "$cur" = "@as []" ] || [ "$cur" = "[]" ]; then cur="['$base']"; else cur="${cur%]}, '$base']"; fi
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$cur" ;;
  esac
  ok "gnome: $GNOME_KEY → screen-ai"
}

bind_plasma() {
  local kw=""; have kwriteconfig6 && kw=kwriteconfig6; [ -z "$kw" ] && have kwriteconfig5 && kw=kwriteconfig5
  mkdir -p "$HOME/.local/share/applications"
  cat >"$HOME/.local/share/applications/screen-ai-toggle.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI
Comment=Ask AI about your screen
Exec=screen-ai --toggle
Icon=screen-ai
Terminal=false
Categories=Utility;
X-KDE-GlobalAccel-CommandShortcut=true
EOF
  [ -z "$kw" ] && { warn "kwriteconfig not found — set the shortcut in System Settings → Shortcuts (command: screen-ai --toggle)"; return 1; }
  $kw --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _launch "$KDE_KEY,none,Screen AI"
  (systemctl --user restart plasma-kglobalaccel.service >/dev/null 2>&1 || true)
  ok "plasma: $KDE_KEY → screen-ai (log out/in if it does not respond)"
}

bind_xfce() {
  have xfconf-query || return 1
  xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$XFCE_KEY" -n -t string -s "screen-ai --toggle"
  ok "xfce: $XFCE_KEY → screen-ai"
}

write_autostart() {
  mkdir -p "$HOME/.config/autostart"
  cat >"$HOME/.config/autostart/screen-ai.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI
Exec=screen-ai
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
}

desktop_entry() {
  mkdir -p "$HOME/.local/share/applications"
  cat >"$HOME/.local/share/applications/screen-ai.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI
Comment=Ask AI about your screen
Exec=screen-ai --toggle
Terminal=false
Categories=Utility;
EOF
  cat >"$HOME/.local/share/applications/screen-ai-settings.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI Settings
Exec=screen-ai --settings
Terminal=false
Categories=Utility;Settings;
EOF
}

# convert_keys "Super+Shift+S" → per-compositor key strings
convert_keys() {
  local k="$1" key rest m
  key="${k##*+}"; rest=""; [[ "$k" == *+* ]] && rest="${k%+*}"
  local n_=() h_=() s_=() g_="" kd_=() x_=""
  for m in ${rest//+/ }; do
    case "$m" in
      Super) n_+=(Mod);  h_+=(SUPER); s_+=(Mod4);  g_+="<Super>";   kd_+=(Meta); x_+="<Super>" ;;
      Shift) n_+=(Shift); h_+=(SHIFT); s_+=(Shift); g_+="<Shift>";   kd_+=(Shift); x_+="<Shift>" ;;
      Ctrl)  n_+=(Ctrl); h_+=(CTRL);  s_+=(Ctrl);  g_+="<Control>"; kd_+=(Ctrl); x_+="<Primary>" ;;
      Alt)   n_+=(Alt);  h_+=(ALT);   s_+=(Mod1);  g_+="<Alt>";     kd_+=(Alt);  x_+="<Alt>" ;;
    esac
  done
  local low; low="$(echo "$key" | tr 'A-Z' 'a-z')"
  local IFS_OLD="$IFS"; IFS='+'
  NIRI_KEY="${n_[*]}+$key"; SWAY_KEY="${s_[*]}+$low"; KDE_KEY="${kd_[*]}+$key"
  IFS=' '; HYPR_MODS="${h_[*]}"; IFS="$IFS_OLD"
  HYPR_KEY="$(echo "$key" | tr a-z A-Z)"; GNOME_KEY="$g_$low"; XFCE_KEY="$x_$low"
}

setup_keybinding() {
  local keys=("Super+Shift+S" "Super+Space" "Ctrl+Alt+Space" "Super+Shift+A" "Alt+Space")
  choose "Shortcut to summon the overlay?" "${keys[@]}"
  local k="${keys[$CHOICE]}"
  convert_keys "$k"

  case "$WM" in
    niri)     bind_niri ;;
    hyprland) bind_hyprland ;;
    sway)     bind_sway ;;
    i3)       bind_i3; write_autostart ;;
    gnome|cinnamon|mate|budgie) bind_gnome && write_autostart ;;
    plasma)   bind_plasma; write_autostart ;;
    xfce)     bind_xfce; write_autostart ;;
    *)
      write_autostart
      if [ "$SESSION" = x11 ]; then ok "x11: the app registers Super+Shift+S / Ctrl+Alt+Space itself"
      else warn "unknown Wayland compositor — bind a key to: screen-ai --toggle"; fi ;;
  esac
}

# ── main ─────────────────────────────────────────────────────────────────────
main() {
  clear 2>/dev/null || true
  banner
  rule
  detect_env

  step "Environment"
  ok "system      $DISTRO_NAME ($ARCH)"
  ok "session     $SESSION"
  ok "compositor  $WM${DE:+  ($DE)}"
  [ -n "$PM" ] && ok "packages    $PM" || warn "packages    unknown package manager"

  step "Dependencies"
  if [ "$NO_DEPS" -eq 1 ]; then note "skipped (--no-deps)"
  elif confirm "Install runtime libraries ($(runtime_pkgs | tr ' ' ','))?" y; then install_deps "$(runtime_pkgs)"
  else note "skipped"; fi

  step "Installing Screen AI"
  pkill -x screen-ai 2>/dev/null; sleep 0.3
  get_binary
  ok "installed → $BIN_DIR/screen-ai"
  case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not in your PATH — add it to your shell profile" ;; esac

  mkdir -p "$SHARE_DIR"
  if have curl; then curl -fsSL "https://raw.githubusercontent.com/$REPO/main/uninstall.sh" -o "$SHARE_DIR/uninstall.sh" 2>/dev/null \
    && chmod +x "$SHARE_DIR/uninstall.sh" && ln -sf "$SHARE_DIR/uninstall.sh" "$BIN_DIR/screen-ai-uninstall"; fi
  desktop_entry

  if [ "$NO_SETUP" -eq 0 ]; then
    step "Setup"
    if [ -s "$CFG_DIR/settings.json" ] && ask_tty && confirm "Existing settings found — keep them?" y; then ok "keeping $CFG_DIR/settings.json"
    else setup_provider; fi
  fi

  if [ "$NO_BIND" -eq 0 ]; then
    step "Shortcut & autostart"
    setup_keybinding
  fi

  step "Launching"
  if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    (nohup "$BIN_DIR/screen-ai" >/dev/null 2>&1 &) ; sleep 1
    pgrep -x screen-ai >/dev/null && ok "running in the background" || warn "could not start — run: screen-ai"
  else note "no display detected — start it from your desktop session"; fi

  printf '\n'; rule
  printf '\n  %s\n\n' "$(gradient "All set.")"
  printf '    %ssummon%s     your shortcut  ·  %sscreen-ai --toggle%s\n' "$BOLD" "$RST" "$DIM" "$RST"
  printf '    %ssettings%s   gear icon in the bar  ·  %sscreen-ai --settings%s\n' "$BOLD" "$RST" "$DIM" "$RST"
  printf '    %suninstall%s  %sscreen-ai-uninstall%s\n\n' "$BOLD" "$RST" "$DIM" "$RST"
}

main

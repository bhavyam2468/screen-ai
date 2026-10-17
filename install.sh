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
  elif [[ "$DE" == *river* ]]; then WM=river
  elif [[ "$DE" == *labwc* ]]; then WM=labwc
  elif [[ "$DE" == *wayfire* ]]; then WM=wayfire
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

filter_installed() {
  local needed=()
  for p in "$@"; do
    case "$PM" in
      pacman) pacman -Q "$p" >/dev/null 2>&1 || needed+=("$p") ;;
      apt)    dpkg -s "$p" 2>/dev/null | grep -q "Status: install ok installed" || needed+=("$p") ;;
      dnf|zypper) rpm -q "$p" >/dev/null 2>&1 || needed+=("$p") ;;
      xbps)   xbps-query -e "$p" >/dev/null 2>&1 || needed+=("$p") ;;
      apk)    apk info -e "$p" >/dev/null 2>&1 || needed+=("$p") ;;
      *)      needed+=("$p") ;;
    esac
  done
  echo "${needed[*]:-}"
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
  [ -z "$pkgs" ] && return 0
  [ -z "$PM" ] && { warn "unknown package manager — install these yourself: $pkgs"; return 0; }
  if [ -n "$SUDO" ] && [ "$(id -u)" -ne 0 ]; then
    if ! sudo -n true 2>/dev/null; then
      printf '  %s!%s administrator password required to install packages:\n' "$AMB" "$RST" >/dev/tty
      sudo -v </dev/tty || { warn "sudo failed — skipping package installation"; return 1; }
    fi
  fi
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
  # Rolling stable release, republished by CI on every push to main.
  local url="https://github.com/$REPO/releases/download/v1-continuous/screen-ai-x86_64-linux.tar.gz" tmp
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/sa.tgz" || { rm -rf "$tmp"; return 1; }
  # Integrity: verify the sha256 sidecar when the release publishes one.
  # (Warn-only — old releases predate checksums.)
  if curl -fsSL "$url.sha256" -o "$tmp/sa.tgz.sha256" 2>/dev/null; then
    want="$(cut -d' ' -f1 "$tmp/sa.tgz.sha256" | tr 'A-Z' 'a-z')"
    got="$(sha256sum "$tmp/sa.tgz" | cut -d' ' -f1)"
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
      echo "checksum mismatch for prebuilt binary, trying source build instead" >&2
      rm -rf "$tmp"; return 1
    fi
  fi
  # Refuse tarballs containing anything but the binary.
  tar -tzf "$tmp/sa.tgz" | grep -qx "screen-ai" || { rm -rf "$tmp"; return 1; }
  tar -xzf "$tmp/sa.tgz" -C "$tmp" && [ -f "$tmp/screen-ai" ] || { rm -rf "$tmp"; return 1; }
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
    local missing_build; missing_build="$(filter_installed $(build_pkgs))"
    if [ -n "$missing_build" ]; then
      confirm "Install missing build tools ($missing_build)?" y && install_deps "$missing_build"
    else
      ok "all build tools already satisfied ($PM)"
    fi
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
  "bg_opacity": $OPACITY,
  "font_family": "libron",
  "theme": "auto"
}
EOF
  chmod 600 "$CFG_DIR/settings.json"
  ok "saved $CFG_DIR/settings.json"
}

# ── keybinding + autostart per environment ───────────────────────────────────
# ── keybinding + autostart per environment ───────────────────────────────────
# Same strategy on every compositor:
#   1. absolute binary path everywhere (session PATH often lacks ~/.local/bin,
#      which silently breaks bare `screen-ai` binds and autostart entries)
#   2. drop-in file + ONE include/source line (never sed-surgery inside blocks)
#   3. backup before touching any user file (the first backup is kept forever)
#   4. validate after writing where possible; roll back on failure
#   5. record every change in the install receipt for clean uninstall
RECEIPT="$SHARE_DIR/receipt"
BIN_ABS="$BIN_DIR/screen-ai"
CFGXDG="${XDG_CONFIG_HOME:-$HOME/.config}"

receipt_set() { # receipt_set KEY VALUE — upsert into the install receipt
  mkdir -p "$SHARE_DIR"; touch "$RECEIPT"
  grep -v "^$1=" "$RECEIPT" >"$RECEIPT.tmp" 2>/dev/null || true
  printf '%s=%s\n' "$1" "$2" >>"$RECEIPT.tmp"
  mv "$RECEIPT.tmp" "$RECEIPT"
}

add_line_once() { # add_line_once FILE LINE
  touch "$1"
  grep -qxF "$2" "$1" 2>/dev/null || printf '%s\n' "$2" >>"$1"
}

backup_once() { # backup_once FILE — keep the FIRST backup forever
  [ -f "$1" ] || return 0
  if [ ! -e "$1.screen-ai-bak" ]; then
    cp -p "$1" "$1.screen-ai-bak" && note "backed up: $1 → $1.screen-ai-bak"
  fi
}

ver_ge() { # ver_ge HAVE WANT → true if HAVE >= WANT
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

# Config resolvers — print the live user config, or fail.
resolve_niri_cfg() {
  for c in "${NIRI_CONFIG:-}" "$CFGXDG/niri/config.kdl" "$HOME/.config/niri/config.kdl"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
resolve_hypr_cfg() {
  for c in "$CFGXDG/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf"; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
resolve_sway_cfg() {
  for c in "$CFGXDG/sway/config" "$HOME/.sway/config"; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
resolve_i3_cfg() {
  # NOTE: i3 ignores XDG_CONFIG_HOME; these are the two user-writable paths.
  for c in "$HOME/.config/i3/config" "$HOME/.i3/config"; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# warn_if_shadowed FILE EREGEX LABEL — our lines are appended last, so they win
# over earlier binds of the same combo; warn so the user can free the old one.
warn_if_shadowed() {
  local hit; hit="$(grep -vi 'screen-ai' "$1" 2>/dev/null | grep -iE "$2" | head -n1)"
  [ -n "$hit" ] && warn "$3: that combo looks already bound — ours is appended last and wins; free the old one if unintended (${hit:0:70}…)"
}

# Convert ONE shortcut choice into every compositor's native format.
convert_keys() { # $1 like "Super+Shift+s"
  local combo="$1" IFS=+
  local mods="${combo%+*}" key="${combo##*+}"
  [ "$mods" = "$combo" ] && mods=""
  local -a n_=() h_=() s_=() kd_=() r_=()
  local g="" x=""
  local m
  for m in $mods; do
    case "$m" in
      Super) n_+=(Mod)  ; h_+=(SUPER); s_+=(Mod4); g+="<Super>" ; kd_+=(Meta) ; x+="<Super>"  ; r_+=(Super) ;;
      Shift) n_+=(Shift); h_+=(SHIFT); s_+=(Shift); g+="<Shift>" ; kd_+=(Shift); x+="<Shift>"  ; r_+=(Shift) ;;
      Ctrl)  n_+=(Ctrl) ; h_+=(CTRL) ; s_+=(Ctrl) ; g+="<Ctrl>"  ; kd_+=(Ctrl) ; x+="<Primary>"; r_+=(Ctrl)  ;;
      Alt)   n_+=(Alt)  ; h_+=(ALT)  ; s_+=(Mod1) ; g+="<Alt>"   ; kd_+=(Alt)  ; x+="<Alt>"    ; r_+=(Alt)   ;;
    esac
  done
  local low; low="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
  local up;  up="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  # NOTE: single letters pair with UPPERCASE when Shift is held — pressing
  # Shift+s produces keysym `S`, so `Mod+Shift+s` would never match in niri
  # and isn't canonical in Qt sequences. (sway/i3/GTK all take lowercase.)
  local skey="$key"
  case "$key" in [a-z]) [[ "${n_[*]}" == *Shift* ]] && skey="$up" ;; esac
  NIRI_KEY="${n_[*]}+$skey"
  # NOTE: join FIRST, then substitute — ${h_[*]//…} would apply per-element
  # (before joining), so the old one-step form silently kept the "+" joins.
  HYPR_MODS="${h_[*]}"; HYPR_MODS="${HYPR_MODS//+/ }"
  HYPR_KEY="$up"
  SWAY_KEY="${s_[*]}+$low"
  GNOME_KEY="$g$low"
  CINNAMON_KEY="$g$low"
  MATE_KEY="$g$low"
  KDE_KEY="${kd_[*]}+$skey"
  XFCE_KEY="$x$low"
  RIVER_MODS="${r_[*]}"
  RIVER_KEY="$up"
  RIVER_SPEC="$RIVER_MODS $RIVER_KEY"
  unset IFS
  [ -z "$HYPR_MODS" ] && HYPR_MODS=SUPER
  if [ -z "$RIVER_MODS" ]; then RIVER_MODS=None; RIVER_SPEC="None $RIVER_KEY"; fi
}

niri_version() { # prints MAJOR.MINOR or fails
  have niri || return 1
  niri --version 2>/dev/null | grep -oE '[0-9]+[.][0-9]+' | head -n1
}

manual_niri() { # [reason] — exact snippet for hand-install
  [ -n "${1:-}" ] && warn "niri: $1"
  note "add this line inside binds { … } in ~/.config/niri/config.kdl:"
  note "    $NIRI_KEY hotkey-overlay-title=\"Screen AI\" { spawn \"$BIN_ABS\" \"--toggle\"; }"
  note "and this at top level:  spawn-at-startup \"$BIN_ABS\""
}

bind_niri() {
  local cfg inc nv
  cfg="$(resolve_niri_cfg)" || { manual_niri "no user config.kdl found"; return 1; }
  nv="$(niri_version)" || { manual_niri "can't determine niri version (is niri installed?)"; return 1; }
  ver_ge "$nv" "25.11" || { manual_niri "niri $nv predates config includes (needs 25.11+)"; return 1; }
  inc="$(dirname "$cfg")/screen-ai.kdl"
  backup_once "$cfg"
  cat >"$inc" <<EOF
// screen-ai — managed by the Screen AI installer.
// Deleting this file plus the matching \`include\` line in config.kdl removes
// everything (the uninstaller does both).
binds {
    $NIRI_KEY hotkey-overlay-title="Screen AI" { spawn "$BIN_ABS" "--toggle"; }
}

spawn-at-startup "$BIN_ABS"

// Fallback-mode rules only: layer-shell needs none of this, but if the
// compositor ever treats the overlay as a normal window, float it.
window-rule {
    match app-id=r#"^screen-ai\$"#
    open-floating true
    draw-border-with-background false
}

window-rule {
    match title=r#"^Screen AI\$"#
    open-floating true
    draw-border-with-background false
}
EOF
  add_line_once "$cfg" 'include "screen-ai.kdl" // screen-ai'
  if niri validate -c "$cfg" >/dev/null 2>&1; then
    warn_if_shadowed "$cfg" "${NIRI_KEY//+/[^A-Za-z]+}" "niri"
    ok "niri $nv: $NIRI_KEY → toggle (validated; hot-reloads automatically)"
  else
    warn "niri rejected the new config — rolled back; add the keybind by hand instead"
    sed -i '/screen-ai[.]kdl/d' "$cfg"; rm -f "$inc"
    manual_niri
    return 1
  fi
}

hypr_version() { # prints version or fails
  local v=""
  if have hyprctl; then v="$(hyprctl version 2>/dev/null | head -n1 | grep -oE '[0-9]+[.][0-9]+([.][0-9]+)?' | head -n1)"; fi
  if [ -z "$v" ] && have hyprland; then v="$(hyprland --version 2>/dev/null | grep -oE '[0-9]+[.][0-9]+([.][0-9]+)?' | head -n1)"; fi
  [ -n "$v" ] && printf '%s' "$v"
}

bind_hyprland() {
  local cfg inc hv kw
  cfg="$(resolve_hypr_cfg)" || { warn "hyprland: no hyprland.conf found"; return 1; }
  hv="$(hypr_version)" || hv=""
  inc="$(dirname "$cfg")/screen-ai.conf"
  backup_once "$cfg"
  {
    echo "# screen-ai — managed by the Screen AI installer; removed by the uninstaller"
    echo
    echo "bind = $HYPR_MODS, $HYPR_KEY, exec, $BIN_ABS --toggle"
    echo "exec-once = $BIN_ABS"
    echo
    if [ -z "$hv" ] || ver_ge "$hv" "0.53"; then
      [ -z "$hv" ] && note "hyprland: version unknown — writing current (≥ 0.53) syntax" >&2
      echo "# Layer + window rules — Hyprland ≥ 0.53 syntax"
      echo "layerrule = blur on, match:namespace ^(screen-ai\$)"
      echo "layerrule = ignore_alpha 0.5, match:namespace ^(screen-ai\$)"
      echo "layerrule = no_anim on, match:namespace ^(screen-ai\$)"
      echo
      echo "# Fallback-mode rules only (layer-shell needs none of this)"
      echo "windowrule = match:class ^(screen-ai\$), float on, no_anim on"
      echo "windowrule = match:title ^(Screen AI\$), float on, no_anim on"
    else
      echo "# Layer + window rules — pre-0.53 syntax (hyprland $hv)"
      echo "layerrule = blur, ^(screen-ai\$)"
      echo "layerrule = ignorealpha 0.5, ^(screen-ai\$)"
      echo "layerrule = noanim, ^(screen-ai\$)"
      echo
      if ver_ge "$hv" "0.48"; then kw=windowrule; else kw=windowrulev2; fi
      echo "$kw = float, noanim, class:^(screen-ai\$)"
      echo "$kw = float, noanim, title:^(Screen AI\$)"
    fi
  } >"$inc"
  add_line_once "$cfg" "source = $inc # screen-ai"
  warn_if_shadowed "$cfg" "bind[a-z]* *=.*${HYPR_MODS// /.*}.*,[ ]*${HYPR_KEY}([ ,]|\$)" "hyprland"
  have hyprctl && hyprctl reload >/dev/null 2>&1
  ok "hyprland${hv:+ $hv}: $HYPR_MODS + $HYPR_KEY → toggle"
}

bind_sway() {
  local cfg inc
  cfg="$(resolve_sway_cfg)" || { warn "sway: no sway config found"; return 1; }
  inc="$(dirname "$cfg")/screen-ai.conf"
  backup_once "$cfg"
  cat >"$inc" <<EOF
# screen-ai — managed by the Screen AI installer; removed by the uninstaller
bindsym $SWAY_KEY exec $BIN_ABS --toggle
exec $BIN_ABS
for_window [app_id="screen-ai"] floating enable, border none
for_window [title="Screen AI"] floating enable, border none
EOF
  add_line_once "$cfg" "include $inc # screen-ai"
  warn_if_shadowed "$cfg" "bindsym.*${SWAY_KEY//+/.*}([^a-zA-Z]|\$)" "sway"
  have swaymsg && swaymsg reload >/dev/null 2>&1
  ok "sway: $SWAY_KEY → toggle"
}

bind_i3() {
  local cfg inc
  cfg="$(resolve_i3_cfg)" || { warn "i3: no i3 config found"; return 1; }
  inc="$(dirname "$cfg")/screen-ai.conf"
  backup_once "$cfg"
  # migrate the inline block written by older installers to the drop-in
  if grep -q "screen-ai BEGIN" "$cfg" 2>/dev/null; then
    sed -i '/# screen-ai BEGIN/,/# screen-ai END/d' "$cfg"
    note "migrated the legacy i3 block to screen-ai.conf"
  fi
  cat >"$inc" <<EOF
# screen-ai — managed by the Screen AI installer; removed by the uninstaller
bindsym $SWAY_KEY exec --no-startup-id $BIN_ABS --toggle
exec --no-startup-id $BIN_ABS
for_window [class="screen-ai"] floating enable, border pixel 0
for_window [title="Screen AI"] floating enable, border pixel 0
EOF
  add_line_once "$cfg" "include $inc # screen-ai"
  warn_if_shadowed "$cfg" "bindsym.*${SWAY_KEY//+/.*}([^a-zA-Z]|\$)" "i3"
  if have i3 && ! i3 -C -c "$cfg" >/dev/null 2>&1; then
    warn "i3 rejected the new config — rolled back"
    sed -i '/screen-ai[.]conf/d' "$cfg"; rm -f "$inc"
    return 1
  fi
  have i3-msg && i3-msg reload >/dev/null 2>&1
  ok "i3: $SWAY_KEY → toggle"
}

bind_river() {
  local init="$CFGXDG/river/init"
  if [ ! -f "$init" ]; then
    note "river: no init script at $init — run this once (and add it to init):"
    note "    riverctl map normal $RIVER_SPEC spawn \"$BIN_ABS --toggle\""
    return 1
  fi
  backup_once "$init"
  add_line_once "$init" "riverctl map normal $RIVER_SPEC spawn \"$BIN_ABS --toggle\" # screen-ai"
  add_line_once "$init" "$BIN_ABS >/dev/null 2>&1 & # screen-ai autostart"
  warn_if_shadowed "$init" "map.*normal.*${RIVER_MODS//+/.*}.* ${RIVER_KEY}([^a-zA-Z]|\$)" "river"
  if have riverctl; then
    if riverctl map normal $RIVER_SPEC spawn "$BIN_ABS --toggle" >/dev/null 2>&1; then
      ok "river: $RIVER_SPEC → toggle (live + in init)"
    else
      warn "riverctl rejected the bind (not on river?) — kept in init for next login"
      return 1
    fi
  else
    ok "river: $RIVER_SPEC → toggle (in init; takes effect next login)"
  fi
}

bind_gnome() {
  have gsettings || { warn "gnome: gsettings not found"; return 1; }
  gsettings list-schemas 2>/dev/null | grep -qx org.gnome.settings-daemon.plugins.media-keys \
    || { warn "gnome: media-keys schema missing"; return 1; }
  local base=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/screen-ai/
  local schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$base"
  local clash; clash="$(gsettings list-recursively org.gnome.desktop.wm.keybindings org.gnome.shell.keybindings org.gnome.settings-daemon.plugins.media-keys 2>/dev/null | grep -v screen-ai | grep -F "'$GNOME_KEY'" | head -n1)"
  [ -n "$clash" ] && warn "gnome: $GNOME_KEY already does something — change it in Settings → Keyboard if needed"
  gsettings set "$schema" name "Screen AI" || return 1
  gsettings set "$schema" command "$BIN_ABS --toggle" || return 1
  gsettings set "$schema" binding "$GNOME_KEY" || return 1
  local cur; cur="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)"
  case "$cur" in *"$base"*) ;; *)
    if [ "$cur" = "@as []" ] || [ "$cur" = "[]" ]; then cur="['$base']"; else cur="${cur%]}, '$base']"; fi
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$cur" || return 1 ;;
  esac
  ok "gnome: $GNOME_KEY → toggle"
}

bind_cinnamon() {
  have gsettings || { warn "cinnamon: gsettings not found"; return 1; }
  gsettings list-schemas 2>/dev/null | grep -qx org.cinnamon.desktop.keybindings \
    || { warn "cinnamon: keybindings schema missing"; return 1; }
  local base=/org/cinnamon/desktop/keybindings/custom-keybindings/
  local sch=org.cinnamon.desktop.keybindings.custom-keybinding
  # reuse our slot if present, else take the first free customN
  local item="" cmd i
  for i in $(seq 0 49); do
    cmd="$(gsettings get "$sch:$base/custom$i/" command 2>/dev/null)" || continue
    if [ "$cmd" = "''" ] || [[ "$cmd" == *screen-ai* ]]; then item="custom$i"; break; fi
  done
  [ -z "$item" ] && { warn "cinnamon: no free custom-keybinding slot"; return 1; }
  gsettings set "$sch:$base/$item/" name "Screen AI" || return 1
  gsettings set "$sch:$base/$item/" command "$BIN_ABS --toggle" || return 1
  gsettings set "$sch:$base/$item/" binding "['$CINNAMON_KEY']" || return 1
  local cur; cur="$(gsettings get org.cinnamon.desktop.keybindings custom-list)"
  case "$cur" in *"'$item'"*) ;; *)
    if [ "$cur" = "@as []" ] || [ "$cur" = "[]" ]; then cur="['$item']"; else cur="${cur%]}, '$item']"; fi
    gsettings set org.cinnamon.desktop.keybindings custom-list "$cur" || return 1 ;;
  esac
  receipt_set CINNAMON_SLOT "$item"
  ok "cinnamon: $CINNAMON_KEY → toggle"
}

bind_mate() {
  have gsettings || { warn "mate: gsettings not found"; return 1; }
  # fixed per-slot schemas: org.mate.desktop.keybindings.customN
  local slots; slots="$(gsettings list-schemas 2>/dev/null | grep -oE 'org[.]mate[.]desktop[.]keybindings[.]custom[0-9]+')"
  [ -z "$slots" ] && { warn "mate: no custom-keybinding schemas found"; return 1; }
  # reuse our slot if present, else take the first free one
  local sch="" cmd s
  for s in $slots; do
    cmd="$(gsettings get "$s" action 2>/dev/null)" || continue
    if [ "$cmd" = "''" ] || [[ "$cmd" == *screen-ai* ]]; then sch="$s"; break; fi
  done
  [ -z "$sch" ] && { warn "mate: no free custom-keybinding slot"; return 1; }
  gsettings set "$sch" name "Screen AI" || return 1
  gsettings set "$sch" action "$BIN_ABS --toggle" || return 1
  gsettings set "$sch" binding "$MATE_KEY" || return 1
  receipt_set MATE_SLOT "${sch##*.}"
  ok "mate: $MATE_KEY → toggle"
}

restart_kglobalaccel() {
  if have systemctl; then
    systemctl --user try-restart plasma-kglobalaccel.service >/dev/null 2>&1 && return 0
  fi
  # non-systemd fallback: bounce the daemon so it re-reads kglobalshortcutsrc
  if have kquitapp6; then kquitapp6 kglobalacceld >/dev/null 2>&1; sleep 0.5
  elif have kquitapp5; then kquitapp5 kglobalaccel5 >/dev/null 2>&1; sleep 0.5
  elif have killall; then killall kglobalacceld kglobalaccel5 >/dev/null 2>&1; sleep 0.5; fi
  local d
  for d in /usr/lib/kglobalacceld /usr/libexec/kglobalacceld /usr/lib/kglobalaccel5 /usr/libexec/kglobalaccel5; do
    if [ -x "$d" ]; then (nohup "$d" >/dev/null 2>&1 &); return 0; fi
  done
  have kglobalacceld && { (nohup kglobalacceld >/dev/null 2>&1 &); return 0; }
  return 1
}

bind_plasma() {
  local kw=""
  have kwriteconfig6 && kw=kwriteconfig6
  [ -z "$kw" ] && have kwriteconfig5 && kw=kwriteconfig5
  mkdir -p "$HOME/.local/share/applications"
  cat >"$HOME/.local/share/applications/screen-ai-toggle.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI
Comment=Ask AI about your screen (managed by the Screen AI installer)
Exec=$BIN_ABS --toggle
Icon=screen-ai
Terminal=false
Categories=Utility;
NoDisplay=true
StartupWMClass=screen-ai
X-KDE-GlobalAccel-CommandShortcut=true
EOF
  [ -z "$kw" ] && { warn "plasma: kwriteconfig not found — set the shortcut in System Settings → Shortcuts (command: $BIN_ABS --toggle)"; return 1; }
  if [ -f "$HOME/.config/kglobalshortcutsrc" ]; then
    local clash; clash="$(grep -F "$KDE_KEY" "$HOME/.config/kglobalshortcutsrc" | grep -v 'screen-ai' | head -n1)"
    [ -n "$clash" ] && warn "plasma: $KDE_KEY already used — change it in System Settings → Shortcuts if needed"
  fi
  # NOTE: Plasma 6 wants the BARE shortcut here — not the old "shortcut,default,name" triple.
  "$kw" --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _k_friendly_name "Screen AI"
  "$kw" --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _launch "$KDE_KEY"
  restart_kglobalaccel || warn "plasma: couldn't refresh the shortcut daemon — log out/in once"
  ok "plasma: $KDE_KEY → toggle (verify in System Settings → Shortcuts)"
}

bind_xfce() {
  have xfconf-query || { warn "xfce: xfconf-query not found"; return 1; }
  # drop any stale screen-ai binding from a previous run (the key may have changed)
  xfconf-query -c xfce4-keyboard-shortcuts -l -p /commands/custom 2>/dev/null | while IFS= read -r prop; do
    v="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" 2>/dev/null)" || continue
    [[ "$v" == *screen-ai* ]] && xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r 2>/dev/null
  done
  xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$XFCE_KEY" -n -t string -s "$BIN_ABS --toggle" || return 1
  receipt_set XFCE_KEY "$XFCE_KEY"
  ok "xfce: $XFCE_KEY → toggle"
}

write_autostart() {
  mkdir -p "$HOME/.config/autostart"
  cat >"$HOME/.config/autostart/screen-ai.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI
Exec=$BIN_ABS
Icon=screen-ai
Terminal=false
Categories=Utility;
NoDisplay=true
StartupWMClass=screen-ai
X-GNOME-Autostart-enabled=true
EOF
}

desktop_entry() {
  mkdir -p "$HOME/.local/share/applications"
  cat >"$HOME/.local/share/applications/screen-ai.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI
Comment=Ask AI about your screen
Exec=$BIN_ABS --toggle
Icon=screen-ai
Terminal=false
Categories=Utility;
StartupWMClass=screen-ai
EOF
  cat >"$HOME/.local/share/applications/screen-ai-settings.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI Settings
Comment=Configure Screen AI providers and hotkeys
Exec=$BIN_ABS --settings
Icon=screen-ai
Terminal=false
Categories=Utility;Settings;
StartupWMClass=screen-ai
EOF
}

install_icon() {
  local png_dir="$HOME/.local/share/icons/hicolor/512x512/apps"
  local svg_dir="$HOME/.local/share/icons/hicolor/scalable/apps"
  mkdir -p "$png_dir" "$svg_dir"
  local png_src="" svg_src="" tmp=""
  # repo checkout / --from-source: use the assets next to this script
  case "$0" in */*)
    [ -f "${0%/*}/assets/icon.png" ] && png_src="${0%/*}/assets/icon.png"
    [ -f "${0%/*}/assets/icon.svg" ] && svg_src="${0%/*}/assets/icon.svg" ;;
  esac
  if { [ -z "$png_src" ] || [ -z "$svg_src" ]; } && have curl; then
    tmp="$(mktemp -d -t screen-ai-icon.XXXXXX 2>/dev/null || true)"
    if [ -n "$tmp" ]; then
      [ -z "$png_src" ] && curl -fsSL --max-time 20 "https://raw.githubusercontent.com/$REPO/main/assets/icon.png" -o "$tmp/icon.png" 2>/dev/null && [ -s "$tmp/icon.png" ] && png_src="$tmp/icon.png"
      [ -z "$svg_src" ] && curl -fsSL --max-time 20 "https://raw.githubusercontent.com/$REPO/main/assets/icon.svg" -o "$tmp/icon.svg" 2>/dev/null && [ -s "$tmp/icon.svg" ] && svg_src="$tmp/icon.svg"
    fi
  fi
  if [ -n "$png_src" ] || [ -n "$svg_src" ]; then
    [ -n "$png_src" ] && cp -f "$png_src" "$png_dir/screen-ai.png" 2>/dev/null
    [ -n "$svg_src" ] && cp -f "$svg_src" "$svg_dir/screen-ai.svg" 2>/dev/null
    ok "installed app icon"
    have gtk-update-icon-cache && gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
  else
    note "couldn't fetch the app icon (cosmetic only)"
  fi
  [ -n "$tmp" ] && rm -rf "$tmp"
  return 0
}

# Which environments to configure: the current session, plus any file-based
# compositor the user clearly uses (existing config) even when not current.
# Live desktop settings (GNOME/Plasma/XFCE/…) are only touched when current.
detect_targets() {
  TARGETS=""
  add_target() { case " $TARGETS " in *" $1 "*) ;; *) TARGETS="$TARGETS $1";; esac; }
  case "$WM" in
    niri|hyprland|sway|i3|river|plasma|gnome|cinnamon|mate|xfce) add_target "$WM" ;;
  esac
  resolve_niri_cfg >/dev/null 2>&1 && add_target niri
  resolve_hypr_cfg >/dev/null 2>&1 && add_target hyprland
  resolve_sway_cfg >/dev/null 2>&1 && add_target sway
  resolve_i3_cfg >/dev/null 2>&1 && add_target i3
  [ -f "$CFGXDG/river/init" ] && add_target river
  TARGETS="${TARGETS# }"
}

print_manual_keys() {
  case "$WM" in
    labwc) note "labwc: add a <keybind> to ~/.config/labwc/rc.xml running: $BIN_ABS --toggle" ;;
    wayfire) note "wayfire: Wayfire Config Manager → Commands → bind a key to: $BIN_ABS --toggle" ;;
    *) warn "unknown compositor ($WM) — bind a key to this command by hand: $BIN_ABS --toggle" ;;
  esac
}

setup_keybinding() {
  local keys=("Super+Shift+s" "Super+Shift+Space" "Ctrl+Alt+p" "Alt+Space")
  local labels=()
  local k
  for k in "${keys[@]}"; do labels+=("$k"); done
  labels+=("Skip (no shortcut)")
  local -a key_opts=()
  for k in "${keys[@]}"; do key_opts+=("$k" ""); done
  key_opts+=("none" "Skip (no shortcut)")
  local sel
  sel="$(choose "Pick a global shortcut" "${key_opts[@]}")"
  [ "$sel" = none ] && { note "skipped global shortcut"; return 0; }
  convert_keys "$sel"

  detect_targets
  local t done_=""
  if [ -n "$TARGETS" ]; then
    note "configuring: $TARGETS"
    for t in $TARGETS; do
      case "$t" in
        niri)     if bind_niri; then done_="$done_ niri"; fi ;;
        hyprland) if bind_hyprland; then done_="$done_ hyprland"; fi ;;
        sway)     if bind_sway; then done_="$done_ sway"; fi ;;
        i3)       if bind_i3; then done_="$done_ i3"; fi ;;
        river)    if bind_river; then done_="$done_ river"; fi ;;
        plasma)   if bind_plasma; then done_="$done_ plasma"; fi ;;
        gnome)    if bind_gnome; then done_="$done_ gnome"; fi ;;
        cinnamon) if bind_cinnamon; then done_="$done_ cinnamon"; fi ;;
        mate)     if bind_mate; then done_="$done_ mate"; fi ;;
        xfce)     if bind_xfce; then done_="$done_ xfce"; fi ;;
      esac
    done
  fi
  case "$WM" in
    labwc|wayfire|wlroots|other)
      if [ "$SESSION" = x11 ]; then
        ok "x11: the app registers its own shortcuts (Super+Shift+S / Ctrl+Alt+Space)"
      else
        print_manual_keys
      fi
      ;;
  esac
  done_="${done_# }"
  receipt_set TARGETS "$done_"
  receipt_set SHORTCUT "$sel"
  write_autostart
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
  local missing; missing="$(filter_installed $(runtime_pkgs))"
  if [ -z "$missing" ]; then
    ok "all runtime dependencies already satisfied ($PM)"
  elif [ "$NO_DEPS" -eq 1 ]; then
    note "skipped (--no-deps)"
  elif confirm "Install missing libraries ($missing)?" y; then
    install_deps "$missing"
  else
    note "skipped"
  fi

  step "Installing Screen AI"
  pkill -x screen-ai 2>/dev/null; sleep 0.3
  get_binary
  ok "installed → $BIN_DIR/screen-ai"
  case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not in your PATH — add it to your shell profile" ;; esac

  mkdir -p "$SHARE_DIR"
  if have curl; then curl -fsSL "https://raw.githubusercontent.com/$REPO/main/uninstall.sh" -o "$SHARE_DIR/uninstall.sh" 2>/dev/null \
    && chmod +x "$SHARE_DIR/uninstall.sh" && ln -sf "$SHARE_DIR/uninstall.sh" "$BIN_DIR/screen-ai-uninstall"; fi
  desktop_entry
  install_icon

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

#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Screen AI — installer
#  curl -fsSL https://raw.githubusercontent.com/bhavyam2468/screen-ai/main/install.sh | bash
#
#  Flags:  --yes  --no-deps  --no-bind  --no-setup  --help
#  Builds the application from source on the installing machine.
# ─────────────────────────────────────────────────────────────────────────────
set -u
REPO="bhavyam2468/screen-ai"
BIN_DIR="${SCREEN_AI_BIN_DIR:-$HOME/.local/bin}"
case "$BIN_DIR" in /*) ;; *) BIN_DIR="$PWD/$BIN_DIR" ;; esac
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
SHARE_DIR="$DATA_HOME/screen-ai"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/screen-ai"
LOG="$(mktemp -t screen-ai-install.XXXXXX.log)"
SOURCE_DIR=""
SOURCE_DIR_OWNED=0
cleanup_source() {
  if [ "$SOURCE_DIR_OWNED" -eq 1 ] && [ -n "$SOURCE_DIR" ] && [ -d "$SOURCE_DIR" ]; then
    rm -rf -- "$SOURCE_DIR"
  fi
  return 0
}
trap cleanup_source EXIT

# Source builds are the only install path. --from-source remains accepted for
# compatibility with older install commands.
ASSUME_YES=0; FROM_SOURCE=1; NO_DEPS=0; NO_BIND=0; NO_SETUP=0
for a in "$@"; do
  case "$a" in
    -y|--yes) ASSUME_YES=1 ;;
    --from-source) FROM_SOURCE=1 ;;
    --no-deps) NO_DEPS=1 ;;
    --no-bind) NO_BIND=1 ;;
    --no-setup) NO_SETUP=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: install.sh [--yes] [--no-deps] [--no-bind] [--no-setup] [--help]
  --yes       Accept safe defaults without interactive prompts
  --no-deps   Do not install runtime or build dependencies; Rust, Node and npm must already be available
  --no-bind   Do not configure compositor shortcuts or autostart
  --no-setup  Keep existing provider settings and skip first-run setup

The installer fetches source and builds Screen AI locally. Run it from a clone
or pipe install.sh to Bash; installation never downloads a prebuilt app binary.
EOF
      exit 0 ;;
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
  gradient "niri · hyprland · sway · plasma · gnome · x11 · broad Linux support"; printf '\n\n'
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
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi
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
  [ -z "$PM" ] && for p in pacman apt-get dnf zypper xbps-install apk; do
    have "$p" && { PM="${p%-get}"; PM="${PM%-install}"; break; }
  done

  SESSION="${XDG_SESSION_TYPE:-}"
  [ -z "$SESSION" ] && { [ -n "${WAYLAND_DISPLAY:-}" ] && SESSION=wayland || { [ -n "${DISPLAY:-}" ] && SESSION=x11 || SESSION=unknown; }; }

  DE="$(printf '%s' "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}" | tr '[:upper:]' '[:lower:]')"
  WM="other"
  if   [ -n "${NIRI_SOCKET:-}" ] || [[ "$DE" == *niri* ]]; then WM=niri
  elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [[ "$DE" == *hypr* ]]; then WM=hyprland
  elif [ -n "${SWAYSOCK:-}" ] || [[ "$DE" == *sway* ]]; then WM=sway
  elif [ -n "${I3SOCK:-}" ] || [[ "$DE" == *i3* ]]; then WM=i3
  elif [[ "$DE" == *plasma* || "$DE" == *kde* ]]; then WM=plasma
  elif [[ "$DE" == *gnome* || "$DE" == *unity* || "$DE" == *budgie* ]]; then WM=gnome
  elif [[ "$DE" == *xfce* ]]; then WM=xfce
  elif [[ "$DE" == *cinnamon* ]]; then WM=cinnamon
  elif [[ "$DE" == *mate* ]]; then WM=mate
  elif [[ "$DE" == *river* ]]; then WM=river
  elif [[ "$DE" == *labwc* ]]; then WM=labwc
  elif [[ "$DE" == *wayfire* ]]; then WM=wayfire
  elif [ -n "${NIRI_CONFIG:-}" ]; then WM=niri
  elif [ -n "${HYPRLAND_CONFIG:-}" ]; then WM=hyprland
  else
    # Process detection is a fallback only; never edit dormant configs just
    # because they happen to exist on disk.
    for pair in 'niri niri' 'Hyprland hyprland' 'sway sway' 'i3 i3' 'river river'; do
      set -- $pair
      if pgrep -u "$(id -u)" -x "$1" >/dev/null 2>&1; then WM="$2"; break; fi
    done
  fi
  if [ -n "${SCREEN_AI_COMPOSITOR:-}" ]; then
    WM="$(printf '%s' "$SCREEN_AI_COMPOSITOR" | tr '[:upper:]' '[:lower:]')"
    note "using SCREEN_AI_COMPOSITOR override: $WM"
  fi
  ARCH="$(uname -m)"
}

# ── dependencies ─────────────────────────────────────────────────────────────
runtime_pkgs() {
  local shot
  case "$WM" in
    niri|hyprland|sway|river|labwc|wayfire) shot=grim ;;
    plasma) shot=spectacle ;;
    gnome) shot=gnome-screenshot ;;
    *) [ "$SESSION" = wayland ] && shot=grim || shot=maim ;;
  esac
  case "$PM" in
    pacman) echo "webkit2gtk-4.1 gtk3 gtk-layer-shell libayatana-appindicator libxdo $shot curl" ;;
    apt)    echo "libwebkit2gtk-4.1-0 libgtk-3-0 libgtk-layer-shell0 libayatana-appindicator3-1 libxdo3 $shot curl" ;;
    dnf)    echo "webkit2gtk4.1 gtk3 gtk-layer-shell libayatana-appindicator-gtk3 libxdo $shot curl" ;;
    zypper) echo "libwebkit2gtk-4_1-0 gtk3 libgtk-layer-shell0 libayatana-appindicator3-1 libxdo3 $shot curl" ;;
    xbps)   echo "webkit2gtk gtk+3 gtk-layer-shell libayatana-appindicator xdotool $shot curl" ;;
    apk)    echo "webkit2gtk-4.1 gtk+3.0 gtk-layer-shell libayatana-appindicator xdotool $shot curl" ;;
  esac
}

build_pkgs() {
  case "$PM" in
    pacman) echo "base-devel curl git nodejs npm rust webkit2gtk-4.1 gtk3 gtk-layer-shell libayatana-appindicator librsvg libxdo openssl pkgconf" ;;
    apt)    echo "build-essential curl git pkg-config nodejs npm rustc cargo libwebkit2gtk-4.1-dev libgtk-3-dev libgtk-layer-shell-dev libayatana-appindicator3-dev librsvg2-dev libxdo-dev libssl-dev" ;;
    dnf)    echo "gcc gcc-c++ make curl git pkgconf-pkg-config nodejs npm rust cargo webkit2gtk4.1-devel gtk3-devel gtk-layer-shell-devel libayatana-appindicator-gtk3-devel librsvg2-devel libxdo-devel openssl-devel" ;;
    zypper) echo "gcc gcc-c++ make curl git pkg-config nodejs npm rust cargo webkit2gtk4_1-devel gtk3-devel gtk-layer-shell-devel libayatana-appindicator3-devel librsvg-devel libxdo-devel libopenssl-devel" ;;
    xbps)   echo "base-devel curl git nodejs npm rust cargo webkit2gtk gtk+3 gtk-layer-shell libayatana-appindicator librsvg-devel xdotool-devel openssl-devel pkg-config" ;;
    apk)    echo "build-base curl git nodejs npm rust cargo webkit2gtk-4.1-dev gtk+3.0-dev gtk-layer-shell-dev libayatana-appindicator-dev librsvg-dev xdotool-dev openssl-dev pkgconf" ;;
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

# ── build from source on the installing machine ────────────────────────────────
ensure_rust() {
  local minimum="1.78.0" version="" cargo_home="${CARGO_HOME:-$HOME/.cargo}" rustup_init="$CACHE_HOME/rustup-init.sh"
  if have rustc && have cargo; then
    version="$(rustc --version 2>/dev/null | awk '{print $2}')"
    if [ -n "$version" ] && ver_ge "$version" "$minimum"; then return 0; fi
  fi

  if [ "$NO_DEPS" -eq 1 ]; then
    echo "Rust $minimum or newer is required. Install a current stable toolchain with rustup, then rerun without --no-deps." >&2
    return 1
  fi
  if ! confirm "Install/update the stable Rust toolchain with rustup?" y; then
    echo "Rust $minimum or newer is required to build Screen AI." >&2
    return 1
  fi

  if have rustup; then
    rustup toolchain install stable --profile minimal >>"$LOG" 2>&1 || {
      tail -n 12 "$LOG" >&2
      return 1
    }
    rustup default stable >>"$LOG" 2>&1 || return 1
  else
    have curl || { echo "curl is required to install rustup" >&2; return 1; }
    mkdir -p "$CACHE_HOME"
    curl -fsSL --retry 2 --max-time 120 https://sh.rustup.rs -o "$rustup_init" || {
      echo "Could not download rustup; install Rust $minimum or newer manually." >&2
      return 1
    }
    sh "$rustup_init" -y --profile minimal --default-toolchain stable --no-modify-path >>"$LOG" 2>&1 || {
      tail -n 12 "$LOG" >&2
      rm -f "$rustup_init"
      return 1
    }
    rm -f "$rustup_init"
  fi

  export PATH="$cargo_home/bin:$PATH"
  have rustc && have cargo || { echo "rustup completed, but rustc/cargo are not on PATH" >&2; return 1; }
  version="$(rustc --version 2>/dev/null | awk '{print $2}')"
  ver_ge "$version" "$minimum" || { echo "Rust $minimum or newer is required (found ${version:-unknown})" >&2; return 1; }
}

bin_ok() {
  [ -x "$1" ] || return 1
  have ldd || return 0
  ! ldd "$1" 2>/dev/null | grep -q "not found"
}

build_from_source() {
  have git || { echo "git is required to fetch the application source" >&2; return 1; }
  ensure_rust || return 1
  have npm || { echo "npm is required to build the application frontend" >&2; return 1; }
  have node || { echo "Node.js 18 or newer is required" >&2; return 1; }
  local node_major script_dir
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [ "$node_major" -ge 18 ] || { echo "Node.js 18 or newer is required (found $(node --version 2>/dev/null || echo missing))" >&2; return 1; }

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
  if [ -n "$script_dir" ] && [ -f "$script_dir/package.json" ] && [ -f "$script_dir/src-tauri/Cargo.toml" ]; then
    SOURCE_DIR="$script_dir"
    note "building the checked-out source at $SOURCE_DIR"
  else
    mkdir -p "$CACHE_HOME"
    SOURCE_DIR="$(mktemp -d "$CACHE_HOME/screen-ai-source.XXXXXX")"
    SOURCE_DIR_OWNED=1
    # build_from_source runs under spin's background subshell, so install the
    # cleanup trap there as well as in the main shell.
    trap cleanup_source EXIT
    git clone --depth 1 "https://github.com/$REPO.git" "$SOURCE_DIR" || return 1
  fi
  (
    set -e
    cd "$SOURCE_DIR"
    npm ci --no-audit --no-fund
    npm run build
    cargo build --locked --release --manifest-path src-tauri/Cargo.toml
  ) || return 1

  local built="$SOURCE_DIR/src-tauri/target/release/screen-ai"
  [ -x "$built" ] || { echo "Build finished without producing $built" >&2; return 1; }
  mkdir -p "$BIN_DIR"
  local staged="$BIN_DIR/.screen-ai.new.$$"
  install -m755 "$built" "$staged" && mv -f "$staged" "$BIN_DIR/screen-ai" || {
    rm -f "$staged"
    return 1
  }
}

get_binary() {
  if [ "$NO_DEPS" -eq 0 ]; then
    local package_list missing_build
    package_list="$(build_pkgs)"
    if [ -z "$PM" ] || [ -z "$package_list" ]; then
      warn "unsupported package manager; install the documented build dependencies manually"
    else
      missing_build="$(filter_installed $package_list)"
      if [ -n "$missing_build" ]; then
        confirm "Install missing build tools and libraries ($missing_build)?" y && install_deps "$missing_build"
      else
        ok "build toolchain and native development libraries already present ($PM)"
      fi
    fi
  fi
  spin "compiling Screen AI locally (first build may take several minutes)" build_from_source || die "source build failed"
  bin_ok "$BIN_DIR/screen-ai" || die "installed binary has unresolved runtime libraries"
}

install_update_tool() {
  mkdir -p "$SHARE_DIR" "$BIN_DIR"
  local src=""
  [ -n "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/update.sh" ] && src="$SOURCE_DIR/update.sh"
  if [ -z "$src" ] && [ -f "${0%/*}/update.sh" ]; then src="${0%/*}/update.sh"; fi
  if [ -n "$src" ]; then
    install -m755 "$src" "$SHARE_DIR/update.sh"
  elif have curl; then
    curl -fsSL --max-time 20 "https://raw.githubusercontent.com/$REPO/main/update.sh" -o "$SHARE_DIR/update.sh" || return 1
    chmod 755 "$SHARE_DIR/update.sh"
  else
    warn "could not install the source-update helper; update via the installer when needed"
    return 1
  fi
  cat >"$BIN_DIR/screen-ai-update" <<EOF
#!/usr/bin/env bash
# screen-ai managed wrapper
XDG_DATA_HOME_DEFAULT=$(printf '%q' "$DATA_HOME")
XDG_CONFIG_HOME_DEFAULT=$(printf '%q' "$CFGXDG")
XDG_CACHE_HOME_DEFAULT=$(printf '%q' "$CACHE_HOME")
export XDG_DATA_HOME="\${XDG_DATA_HOME:-\$XDG_DATA_HOME_DEFAULT}"
export XDG_CONFIG_HOME="\${XDG_CONFIG_HOME:-\$XDG_CONFIG_HOME_DEFAULT}"
export XDG_CACHE_HOME="\${XDG_CACHE_HOME:-\$XDG_CACHE_HOME_DEFAULT}"
SCREEN_AI_INSTALL_PATH=$(printf '%q' "$BIN_ABS") exec $(printf '%q' "$SHARE_DIR/update.sh") "\$@"
EOF
  chmod 755 "$BIN_DIR/screen-ai-update"
  receipt_set UPDATER_WRAPPER "$BIN_DIR/screen-ai-update"
  ok "source updater installed → $BIN_DIR/screen-ai-update"
}

install_uninstaller() {
  mkdir -p "$SHARE_DIR" "$BIN_DIR"
  local src=""
  [ -n "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/uninstall.sh" ] && src="$SOURCE_DIR/uninstall.sh"
  if [ -z "$src" ] && [ -f "${0%/*}/uninstall.sh" ]; then src="${0%/*}/uninstall.sh"; fi
  if [ -n "$src" ]; then
    install -m755 "$src" "$SHARE_DIR/uninstall.sh"
  elif have curl; then
    curl -fsSL --max-time 20 "https://raw.githubusercontent.com/$REPO/main/uninstall.sh" -o "$SHARE_DIR/uninstall.sh" || return 1
    chmod 755 "$SHARE_DIR/uninstall.sh"
  else
    warn "could not install the uninstaller helper"
    return 1
  fi
  cat >"$BIN_DIR/screen-ai-uninstall" <<EOF
#!/usr/bin/env bash
# screen-ai managed wrapper
XDG_DATA_HOME_DEFAULT=$(printf '%q' "$DATA_HOME")
XDG_CONFIG_HOME_DEFAULT=$(printf '%q' "$CFGXDG")
export XDG_DATA_HOME="\${XDG_DATA_HOME:-\$XDG_DATA_HOME_DEFAULT}"
export XDG_CONFIG_HOME="\${XDG_CONFIG_HOME:-\$XDG_CONFIG_HOME_DEFAULT}"
SCREEN_AI_BIN_DIR=$(printf '%q' "$BIN_DIR") exec $(printf '%q' "$SHARE_DIR/uninstall.sh") "\$@"
EOF
  chmod 755 "$BIN_DIR/screen-ai-uninstall"
  receipt_set UNINSTALL_WRAPPER "$BIN_DIR/screen-ai-uninstall"
  ok "uninstaller installed → $BIN_DIR/screen-ai-uninstall"
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
  "theme": "auto"
}
EOF
  chmod 600 "$CFG_DIR/settings.json"
  ok "saved $CFG_DIR/settings.json"
}

# ── keybinding + autostart per environment ───────────────────────────────────
SHORTCUT_ENABLED=1
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
NIRI_KEY="" HYPR_MODS="SUPER" HYPR_KEY="" SWAY_KEY=""
GNOME_KEY="" CINNAMON_KEY="" MATE_KEY="" KDE_KEY="" XFCE_KEY=""
RIVER_MODS="" RIVER_KEY="" RIVER_SPEC=""

receipt_set() { # receipt_set KEY VALUE — upsert into the install receipt
  mkdir -p "$SHARE_DIR"; touch "$RECEIPT"
  grep -v "^$1=" "$RECEIPT" >"$RECEIPT.tmp" 2>/dev/null || true
  printf '%s=%s\n' "$1" "$2" >>"$RECEIPT.tmp"
  mv "$RECEIPT.tmp" "$RECEIPT"
}

# Refuse to edit symlinked configuration files or any file reached through a
# symlinked parent (dotfile managers commonly use these paths intentionally).
safe_to_edit() {
  local path="$1" walk="$1"
  case "$walk" in /*) ;; *) walk="$PWD/$walk" ;; esac
  while [ "$walk" != / ]; do
    [ ! -L "$walk" ] || return 1
    walk="$(dirname "$walk")"
  done
  if [ -e "$path" ]; then
    [ -f "$path" ] && [ -w "$path" ]
  else
    [ -d "$(dirname "$path")" ] && [ -w "$(dirname "$path")" ]
  fi
}

add_line_once() { # add_line_once FILE LINE — append without disturbing user content
  local file="$1" line="$2" last=""
  safe_to_edit "$file" || { warn "refusing to edit a symlinked or read-only config: $file"; return 1; }
  [ -e "$file" ] || : >"$file"
  if ! grep -qxF "$line" "$file" 2>/dev/null; then
    [ ! -s "$file" ] || last="$(tail -c 1 "$file" 2>/dev/null || true)"
    [ -z "$last" ] || printf '\n' >>"$file"
    printf '%s\n' "$line" >>"$file"
  fi
}

remove_exact_line() { # remove_exact_line FILE LINE
  local file="$1" line="$2" tmp
  [ -f "$file" ] || return 0
  safe_to_edit "$file" || { warn "refusing to edit a symlinked or read-only config: $file"; return 1; }
  tmp="$(mktemp "$(dirname "$file")/.screen-ai-edit.XXXXXX")" || return 1
  grep -vxF "$line" "$file" >"$tmp" || true
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

backup_once() { # backup_once FILE — keep the FIRST backup forever
  local file="$1" backup="$1.screen-ai-bak"
  [ -f "$file" ] || return 0
  [ ! -L "$file" ] || { warn "not backing up symlinked config: $file"; return 1; }
  if [ -e "$backup" ] || [ -L "$backup" ]; then
    [ -f "$backup" ] && [ ! -L "$backup" ] || { warn "refusing to use a non-regular or symlinked backup path: $backup"; return 1; }
    return 0
  fi
  cp -p "$file" "$backup" || { warn "could not back up config before editing: $file"; return 1; }
  note "backed up: $file → $backup"
}

MANAGED_MARKER="screen-ai managed by the Screen AI installer"
managed_file_path() { # managed_file_path DIR STEM EXT
  local dir="$1" stem="$2" ext="$3" path="$1/$2$3" suffix=1
  while [ -e "$path" ] && ! grep -Fq "$MANAGED_MARKER" "$path" 2>/dev/null; do
    path="$dir/$stem-$suffix$ext"
    suffix=$((suffix + 1))
  done
  printf '%s' "$path"
}

desktop_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//%/%%}"
  printf '"%s"' "$value"
}

desktop_managed_path() { # DIR STEM NAME EXEC_PREFIX
  local dir="$1" stem="$2" name="$3" exec_path="$4" preferred="$1/$2.desktop" quoted
  exec_path="${exec_path#Exec=}"
  quoted="$(desktop_quote "$exec_path")"
  if [ -e "$preferred" ]; then
    if ! { grep -qxF "Name=$name" "$preferred" && \
         { grep -Fq "Exec=$exec_path" "$preferred" || grep -Fq "Exec=$quoted" "$preferred"; }; }; then
      preferred="$(managed_file_path "$dir" "$stem-managed" .desktop)"
    fi
  fi
  printf '%s' "$preferred"
}

shell_quote() {
  local value="$1"
  value="${value//\'/\'\\\'\'}"
  printf "'%s'" "$value"
}

kdl_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "$value"
}
lua_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
}

ver_ge() { # ver_ge HAVE WANT → true if HAVE >= WANT; needs only POSIX awk
  awk -v have="$1" -v want="$2" '
    function part(value) { sub(/[^0-9].*$/, "", value); return value + 0 }
    BEGIN {
      split(have, h, "[.]"); split(want, w, "[.]")
      for (i = 1; i <= 4; i++) {
        hp = part(h[i]); wp = part(w[i])
        if (hp > wp) exit 0
        if (hp < wp) exit 1
      }
      exit 0
    }'
}

# Config resolvers — follow the compositor's active config path, not every file
# left over from a previously installed compositor.
resolve_niri_cfg() {
  for c in "${NIRI_CONFIG:-}" "$CFGXDG/niri/config.kdl" "$HOME/.config/niri/config.kdl"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
resolve_hypr_cfg() {
  if [ -n "${HYPRLAND_CONFIG:-}" ] && [ -f "$HYPRLAND_CONFIG" ]; then
    printf '%s' "$HYPRLAND_CONFIG"; return 0
  fi
  for c in "$CFGXDG/hypr/hyprland.lua" "$CFGXDG/hypr/hyprland.conf" \
           "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.conf"; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
resolve_sway_cfg() {
  for c in "${SWAY_CONFIG:-}" "$CFGXDG/sway/config" "$HOME/.sway/config"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
resolve_i3_cfg() {
  # i3 traditionally ignores XDG_CONFIG_HOME; accept its documented user paths.
  for c in "$CFGXDG/i3/config" "$HOME/.config/i3/config" "$HOME/.i3/config"; do
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
  note "No config was changed. Add this command at top level in config.kdl:"
  note "spawn-at-startup $(kdl_quote "$BIN_ABS")"
  if [ "$SHORTCUT_ENABLED" -eq 1 ]; then
    note "and add this key inside your binds { } block (or add a new block):"
    note "  $NIRI_KEY hotkey-overlay-title=\"Screen AI\" { spawn $(kdl_quote "$BIN_ABS") \"--toggle\"; }"
  fi
}

migrate_legacy_niri() {
  local cfg="$1" old="$(dirname "$1")/screen-ai.kdl"
  if [ -f "$old" ] && grep -Eqi 'managed by the Screen AI installer' "$old"; then
    remove_exact_line "$cfg" 'include "screen-ai.kdl" // screen-ai' || return 1
    rm -f "$old"
    note "removed the previous installer-managed niri drop-in"
  fi
}

bind_niri() {
  local cfg dir inc nv include_line temp had_inc=0 old=""
  cfg="$(resolve_niri_cfg)" || { manual_niri "no user config.kdl found"; return 1; }
  safe_to_edit "$cfg" || { manual_niri "config is symlinked or read-only; left it untouched"; return 1; }
  nv="$(niri_version)" || { manual_niri "can't determine niri version (is niri installed?)"; return 1; }
  ver_ge "$nv" "25.11" || { manual_niri "Niri $nv predates top-level config includes"; return 1; }
  dir="$(dirname "$cfg")"
  inc="$(managed_file_path "$dir" screen-ai-managed .kdl)"
  safe_to_edit "$inc" || { manual_niri "managed drop-in is symlinked or read-only; left it untouched"; return 1; }
  case "$inc" in *[[:space:]]*) manual_niri "config path contains spaces; no files were changed"; return 1 ;; esac
  include_line="include \"$(basename "$inc")\" // screen-ai managed"
  if [ -f "$inc" ]; then
    had_inc=1
    old="$(mktemp)" || return 1
    cp -p "$inc" "$old" || { rm -f "$old"; return 1; }
  fi
  backup_once "$cfg" && backup_once "$inc" || { [ -n "$old" ] && rm -f "$old"; return 1; }
  temp="$(mktemp "$(dirname "$inc")/.screen-ai.XXXXXX")" || return 1
  cat >"$temp" <<EOF
// $MANAGED_MARKER
// Remove the marked include from config.kdl and this file to uninstall.
$([ "$SHORTCUT_ENABLED" -eq 1 ] && printf 'binds {\n    %s hotkey-overlay-title="Screen AI" { spawn %s "--toggle"; }\n}\n' "$NIRI_KEY" "$(kdl_quote "$BIN_ABS")")
spawn-at-startup $(kdl_quote "$BIN_ABS")
EOF
  chmod 600 "$temp"
  mv -f "$temp" "$inc" || { [ -n "$old" ] && rm -f "$old"; return 1; }
  add_line_once "$cfg" "$include_line" || { rm -f "$inc"; [ -n "$old" ] && rm -f "$old"; manual_niri "could not add a managed include"; return 1; }
  if ! niri validate -c "$cfg" >/dev/null 2>&1; then
    remove_exact_line "$cfg" "$include_line"
    if [ "$had_inc" -eq 1 ] && [ -n "$old" ]; then mv -f "$old" "$inc"; else rm -f "$inc"; fi
    warn "niri rejected the managed config; rolled back the installer change"
    manual_niri "please check your current config and add the shortcut manually"
    return 1
  fi
  [ -n "$old" ] && rm -f "$old"
  migrate_legacy_niri "$cfg" || warn "could not remove an older Screen AI niri include"
  if ! niri validate -c "$cfg" >/dev/null 2>&1; then
    warn "niri config changed while migrating the previous drop-in; check it with 'niri validate'"
  fi
  receipt_set BIN_DIR "$BIN_DIR"
  receipt_set NIRI_CONFIG "$cfg"
  receipt_set NIRI_DROPIN "$inc"
  receipt_set NIRI_INCLUDE "$include_line"
  if [ "$SHORTCUT_ENABLED" -eq 1 ]; then
    warn_if_shadowed "$cfg" "${NIRI_KEY//+/[^A-Za-z]+}" "niri"
    ok "niri $nv: $NIRI_KEY → toggle (managed drop-in; validated)"
  else
    ok "niri $nv: startup only (managed drop-in; validated)"
  fi
}

hypr_version() { # prints version or fails
  local v=""
  if have hyprctl; then v="$(hyprctl version 2>/dev/null | head -n1 | grep -oE '[0-9]+[.][0-9]+([.][0-9]+)?' | head -n1)"; fi
  if [ -z "$v" ] && have Hyprland; then v="$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+[.][0-9]+([.][0-9]+)?' | head -n1)"; fi
  [ -n "$v" ] && printf '%s' "$v"
}

manual_hypr() {
  [ -n "${1:-}" ] && warn "hyprland: $1"
  if [[ "${2:-}" == lua ]]; then
    local lua_command; lua_command="$(lua_escape "$(shell_quote "$BIN_ABS")")"
    if [ "$SHORTCUT_ENABLED" -eq 1 ]; then
      note "add a bind in your hyprland.lua: hl.bind(\"$HYPR_MODS + $HYPR_KEY\", hl.dsp.exec_cmd(\"$lua_command --toggle\"))"
    fi
    note "and launch the tray at hyprland.start with hl.exec_cmd(\"$lua_command\")."
  else
    if [ "$SHORTCUT_ENABLED" -eq 1 ]; then
      note "add a bind in your active hyprland.conf: bind = $HYPR_MODS, $HYPR_KEY, exec, $(shell_quote "$BIN_ABS") --toggle"
    fi
    note "and add: exec-once = $(shell_quote "$BIN_ABS")"
  fi
}

migrate_legacy_hypr() {
  local dir="$1" cfg="$2" old="$1/screen-ai.conf"
  if [ -f "$old" ] && grep -Eqi 'managed by the Screen AI installer' "$old"; then
    case "$cfg" in
      *.conf) sed -i '\|^[[:space:]]*source = .*screen-ai[.]conf # screen-ai[[:space:]]*$|d' "$cfg" ;;
      *.lua)
        # A dormant legacy hyprland.conf may still be used if the user
        # switches back from Lua. Remove its include before deleting the old
        # drop-in; otherwise preserve it rather than break that config.
        local old_cfg="$dir/hyprland.conf"
        if [ ! -f "$old_cfg" ] || ! grep -Eq '^[[:space:]]*source = .*screen-ai[.]conf # screen-ai[[:space:]]*$' "$old_cfg"; then
          note "left the legacy Hyprland drop-in in place for config-switch safety"
          return 0
        fi
        safe_to_edit "$old_cfg" || { note "left the legacy Hyprland drop-in; old config is not safely editable"; return 0; }
        sed -i '/^[[:space:]]*source = .*screen-ai[.]conf # screen-ai[[:space:]]*$/d' "$old_cfg" || return 0
        ;;
    esac
    rm -f "$old"
    note "removed the previous installer-managed Hyprland drop-in"
  fi
}

bind_hyprland() {
  local cfg dir inc hv include_line temp had_inc=0 old="" key_expr command_lua module_name
  cfg="$(resolve_hypr_cfg)" || { manual_hypr "no active hyprland.lua or hyprland.conf was found"; return 1; }
  safe_to_edit "$cfg" || { manual_hypr "active config is symlinked or read-only; left it untouched"; return 1; }
  dir="$(dirname "$cfg")"
  hv="$(hypr_version)" || hv="unknown"
  if [[ "$hv" != unknown ]] && ver_ge "$hv" "0.55" && [[ "$cfg" == *.conf ]] && [ -z "${HYPRLAND_CONFIG:-}" ]; then
    manual_hypr "Hyprland $hv uses Lua; found only a legacy .conf, so no inactive config was edited" lua
    return 1
  fi
  if [[ "$hv" != unknown ]] && ! ver_ge "$hv" "0.55" && [[ "$cfg" == *.lua ]]; then
    manual_hypr "Hyprland $hv predates Lua configuration; no config was changed"
    return 1
  fi
  case "$cfg" in
    *.lua)
      inc="$(managed_file_path "$dir" screen_ai_managed .lua)"
      safe_to_edit "$inc" || { manual_hypr "managed module is symlinked or read-only; left it untouched" lua; return 1; }
      module_name="$(basename "$inc" .lua)"
      include_line="require(\"./$module_name\") -- screen-ai managed"
      ;;
    *.conf)
      inc="$(managed_file_path "$dir" screen-ai-managed .conf)"
      safe_to_edit "$inc" || { manual_hypr "managed drop-in is symlinked or read-only; left it untouched"; return 1; }
      case "$inc" in *[[:space:]]*) manual_hypr "config path contains spaces; no files were changed"; return 1 ;; esac
      include_line="source = $inc # screen-ai managed"
      ;;
    *) manual_hypr "unsupported config file format: $cfg"; return 1 ;;
  esac
  case "$inc" in *[[:space:]]*) manual_hypr "config path contains spaces; no files were changed" "${cfg##*.}"; return 1 ;; esac
  if [ -f "$inc" ]; then
    had_inc=1
    old="$(mktemp)" || return 1
    cp -p "$inc" "$old" || { rm -f "$old"; return 1; }
  fi
  backup_once "$cfg" && backup_once "$inc" || { [ -n "$old" ] && rm -f "$old"; return 1; }
  temp="$(mktemp "$(dirname "$inc")/.screen-ai.XXXXXX")" || return 1

  if [[ "$cfg" == *.lua ]]; then
    local key_expr=""
    [ "$HYPR_MODS" = SUPER ] && key_expr="SUPER + $HYPR_KEY" || key_expr="${HYPR_MODS// / + } + $HYPR_KEY"
    command_lua="$(lua_escape "$(shell_quote "$BIN_ABS")")"
    cat >"$temp" <<EOF
-- $MANAGED_MARKER
local screen_ai_executable = "$command_lua"
$([ "$SHORTCUT_ENABLED" -eq 1 ] && printf 'hl.bind("%s", hl.dsp.exec_cmd(screen_ai_executable .. " --toggle"))' "$key_expr")
hl.on("hyprland.start", function()
    hl.exec_cmd(screen_ai_executable)
end)
EOF
  else
    cat >"$temp" <<EOF
# $MANAGED_MARKER
$([ "$SHORTCUT_ENABLED" -eq 1 ] && printf 'bind = %s, %s, exec, %s --toggle\n' "$HYPR_MODS" "$HYPR_KEY" "$(shell_quote "$BIN_ABS")")exec-once = $(shell_quote "$BIN_ABS")
EOF
  fi
  chmod 600 "$temp"
  mv -f "$temp" "$inc" || { [ -n "$old" ] && rm -f "$old"; return 1; }
  add_line_once "$cfg" "$include_line" || { rm -f "$inc"; [ -n "$old" ] && rm -f "$old"; manual_hypr "could not add a managed include" "${cfg##*.}"; return 1; }

  # Files managed by the pre-Lua installer are safe to migrate once the new
  # module is attached. Never touch hand-written .conf/.lua files.
  if have hyprctl && ! hyprctl reload >/dev/null 2>&1; then
    warn "hyprland rejected the updated config; rolling back Screen AI's managed entry"
    remove_exact_line "$cfg" "$include_line"
    if [ "$had_inc" -eq 1 ] && [ -n "$old" ]; then mv -f "$old" "$inc"; else rm -f "$inc"; fi
    return 1
  fi
  migrate_legacy_hypr "$dir" "$cfg"
  if have hyprctl; then hyprctl reload >/dev/null 2>&1 || warn "hyprland: old managed entry was removed; run 'hyprctl reload' once more"; fi
  [ -n "$old" ] && rm -f "$old"
  receipt_set HYPR_CONFIG "$cfg"
  receipt_set HYPR_DROPIN "$inc"
  receipt_set HYPR_INCLUDE "$include_line"
  if [ "$SHORTCUT_ENABLED" -eq 1 ]; then
    if [[ "$cfg" == *.lua ]]; then
      ok "hyprland $hv (Lua): $HYPR_MODS + $HYPR_KEY → toggle (managed module)"
    else
      ok "hyprland $hv (hyprlang): $HYPR_MODS + $HYPR_KEY → toggle (managed drop-in)"
    fi
  else
    ok "hyprland $hv: startup only (managed integration)"
  fi
}

migrate_legacy_sway() {
  local cfg="$1" old="$(dirname "$1")/screen-ai.conf"
  if [ -f "$old" ] && grep -Eqi 'managed by the Screen AI installer' "$old"; then
    sed -i '\|^[[:space:]]*include .*screen-ai[.]conf # screen-ai[[:space:]]*$|d' "$cfg"
    rm -f "$old"
    note "removed the previous installer-managed Sway drop-in"
  fi
}

bind_sway() {
  local cfg inc dir include_line temp old="" had_inc=0 command
  cfg="$(resolve_sway_cfg)" || { warn "sway: no active config found; no files were changed"; return 1; }
  safe_to_edit "$cfg" || { warn "sway: config is symlinked or read-only; left it untouched"; return 1; }
  dir="$(dirname "$cfg")"
  inc="$(managed_file_path "$dir" screen-ai-managed .conf)"
  safe_to_edit "$inc" || { warn "sway: managed drop-in is symlinked or read-only; left it untouched"; return 1; }
  case "$inc" in *[[:space:]]*) warn "sway: config path contains spaces; left it untouched"; return 1 ;; esac
  include_line="include $inc # screen-ai managed"
  if [ -f "$inc" ]; then
    had_inc=1
    old="$(mktemp)" || return 1
    cp -p "$inc" "$old" || { rm -f "$old"; return 1; }
  fi
  backup_once "$cfg" && backup_once "$inc" || { [ -n "$old" ] && rm -f "$old"; return 1; }
  temp="$(mktemp "$(dirname "$inc")/.screen-ai.XXXXXX")" || return 1
  command="$(shell_quote "$BIN_ABS") --toggle"
  cat >"$temp" <<EOF
# $MANAGED_MARKER
$([ "$SHORTCUT_ENABLED" -eq 1 ] && printf 'bindsym %s exec %s\n' "$SWAY_KEY" "$command")exec $(shell_quote "$BIN_ABS")
EOF
  chmod 600 "$temp"
  mv -f "$temp" "$inc" || { [ -n "$old" ] && rm -f "$old"; return 1; }
  add_line_once "$cfg" "$include_line" || { rm -f "$inc"; [ -n "$old" ] && rm -f "$old"; return 1; }
  if have sway && ! sway -C -c "$cfg" >/dev/null 2>&1; then
    warn "sway rejected the new config; rolling back the managed include"
    remove_exact_line "$cfg" "$include_line"
    if [ "$had_inc" -eq 1 ] && [ -n "$old" ]; then mv -f "$old" "$inc"; else rm -f "$inc"; fi
    return 1
  fi
  migrate_legacy_sway "$cfg"
  have swaymsg && swaymsg reload >/dev/null 2>&1 || true
  [ -n "$old" ] && rm -f "$old"
  receipt_set SWAY_CONFIG "$cfg"
  receipt_set SWAY_DROPIN "$inc"
  receipt_set SWAY_INCLUDE "$include_line"
  if [ "$SHORTCUT_ENABLED" -eq 1 ]; then ok "sway: $SWAY_KEY → toggle (managed drop-in)"; else ok "sway: startup only (managed drop-in)"; fi
}

migrate_legacy_i3() {
  local cfg="$1" old="$(dirname "$1")/screen-ai.conf"
  if [ -f "$old" ] && grep -Eqi 'managed by the Screen AI installer' "$old"; then
    sed -i '\|^[[:space:]]*include .*screen-ai[.]conf # screen-ai[[:space:]]*$|d' "$cfg"
    rm -f "$old"
    note "removed the previous installer-managed i3 drop-in"
  fi
}

bind_i3() {
  local cfg inc dir include_line temp old="" had_inc=0 command
  cfg="$(resolve_i3_cfg)" || { warn "i3: no active config found; no files were changed"; return 1; }
  safe_to_edit "$cfg" || { warn "i3: config is symlinked or read-only; left it untouched"; return 1; }
  dir="$(dirname "$cfg")"
  inc="$(managed_file_path "$dir" screen-ai-managed .conf)"
  safe_to_edit "$inc" || { warn "i3: managed drop-in is symlinked or read-only; left it untouched"; return 1; }
  case "$inc" in *[[:space:]]*) warn "i3: config path contains spaces; left it untouched"; return 1 ;; esac
  include_line="include $inc # screen-ai managed"
  if [ -f "$inc" ]; then
    had_inc=1
    old="$(mktemp)" || return 1
    cp -p "$inc" "$old" || { rm -f "$old"; return 1; }
  fi
  backup_once "$cfg" && backup_once "$inc" || { [ -n "$old" ] && rm -f "$old"; return 1; }
  temp="$(mktemp "$(dirname "$inc")/.screen-ai.XXXXXX")" || return 1
  command="$(shell_quote "$BIN_ABS") --toggle"
  cat >"$temp" <<EOF
# $MANAGED_MARKER
$([ "$SHORTCUT_ENABLED" -eq 1 ] && printf 'bindsym %s exec --no-startup-id %s\n' "$SWAY_KEY" "$command")exec --no-startup-id $(shell_quote "$BIN_ABS")
EOF
  chmod 600 "$temp"
  mv -f "$temp" "$inc" || { [ -n "$old" ] && rm -f "$old"; return 1; }
  add_line_once "$cfg" "$include_line" || { rm -f "$inc"; [ -n "$old" ] && rm -f "$old"; return 1; }
  if have i3 && ! i3 -C -c "$cfg" >/dev/null 2>&1; then
    warn "i3 rejected the new config; rolling back the managed include"
    remove_exact_line "$cfg" "$include_line"
    if [ "$had_inc" -eq 1 ] && [ -n "$old" ]; then mv -f "$old" "$inc"; else rm -f "$inc"; fi
    return 1
  fi
  migrate_legacy_i3 "$cfg"
  have i3-msg && i3-msg reload >/dev/null 2>&1 || true
  [ -n "$old" ] && rm -f "$old"
  receipt_set I3_CONFIG "$cfg"
  receipt_set I3_DROPIN "$inc"
  receipt_set I3_INCLUDE "$include_line"
  if [ "$SHORTCUT_ENABLED" -eq 1 ]; then
    ok "i3: $SWAY_KEY → toggle (managed drop-in; validated when i3 is available)"
  else
    ok "i3: startup only (managed drop-in; validated when i3 is available)"
  fi
}

bind_river() {
  local init="$CFGXDG/river/init" bind_line start_line
  if [ ! -f "$init" ]; then
    note "river: no init script at $init; no files were changed"
    if [ "$SHORTCUT_ENABLED" -eq 1 ]; then
      note "add: riverctl map normal $RIVER_SPEC spawn \"$(shell_quote "$BIN_ABS") --toggle\""
    fi
    note "add this startup command to init: $(shell_quote "$BIN_ABS") >/dev/null 2>&1 &"
    return 1
  fi
  safe_to_edit "$init" || { warn "river: init script is symlinked or read-only; left it untouched"; return 1; }
  backup_once "$init" || return 1
  bind_line=""
  start_line="$(shell_quote "$BIN_ABS") >/dev/null 2>&1 & # screen-ai managed autostart"
  if [ "$SHORTCUT_ENABLED" -eq 1 ]; then
    bind_line="riverctl map normal $RIVER_SPEC spawn \"$(shell_quote "$BIN_ABS") --toggle\" # screen-ai managed"
    add_line_once "$init" "$bind_line" || return 1
    warn_if_shadowed "$init" "map.*normal.*${RIVER_MODS//+/.*}.* ${RIVER_KEY}([^a-zA-Z]|\$)" "river"
    if have riverctl && ! riverctl map normal $RIVER_SPEC spawn "$(shell_quote "$BIN_ABS") --toggle" >/dev/null 2>&1; then
      warn "riverctl rejected this binding in the active session; kept it in init for review"
      return 1
    fi
  fi
  add_line_once "$init" "$start_line" || return 1
  receipt_set RIVER_INIT "$init"
  receipt_set RIVER_BIND "$bind_line"
  receipt_set RIVER_START "$start_line"
  if [ "$SHORTCUT_ENABLED" -eq 1 ]; then ok "river: $RIVER_SPEC → toggle (managed init entries)"; else ok "river: startup only (managed init entry)"; fi
}

bind_gnome() {
  have gsettings || { warn "gnome: gsettings not found"; return 1; }
  gsettings list-schemas 2>/dev/null | grep -qx org.gnome.settings-daemon.plugins.media-keys \
    || { warn "gnome: media-keys schema missing"; return 1; }
  local root=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
  local schema_root=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding
  local cur base schema command_value clash index suffix
  local expected="$(shell_quote "$BIN_ABS") --toggle"
  cur="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)" || return 1
  base=""
  for index in $(seq 0 49); do
    suffix="screen-ai"
    [ "$index" -eq 0 ] || suffix="screen-ai-$index"
    local candidate="$root/$suffix/"
    if [[ "$cur" == *"$candidate"* ]]; then
      command_value="$(gsettings get "$schema_root:$candidate" command 2>/dev/null || true)"
      if [[ "$command_value" == *"$BIN_ABS"* && "$command_value" == *screen-ai* ]]; then
        base="$candidate"
        break
      fi
    else
      base="$candidate"
      break
    fi
  done
  [ -n "$base" ] || { warn "gnome: no free custom-keybinding path"; return 1; }
  schema="$schema_root:$base"
  local accelerator="$GNOME_KEY"
  clash="$(gsettings list-recursively org.gnome.desktop.wm.keybindings org.gnome.shell.keybindings org.gnome.settings-daemon.plugins.media-keys 2>/dev/null | grep -v screen-ai | grep -F "'$accelerator'" | head -n1)"
  [ -n "$clash" ] && warn "gnome: $GNOME_KEY already does something — change it in Settings → Keyboard if needed"
  gsettings set "$schema" name "Screen AI" || return 1
  gsettings set "$schema" command "$expected" || return 1
  gsettings set "$schema" binding "$GNOME_KEY" || return 1
  case "$cur" in *"$base"*) ;; *)
    if [ "$cur" = "@as []" ] || [ "$cur" = "[]" ]; then cur="['$base']"; else cur="${cur%]}, '$base']"; fi
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$cur" || return 1 ;;
  esac
  receipt_set GNOME_PATH "$base"
  ok "gnome: $GNOME_KEY → toggle"
}

bind_cinnamon() {
  have gsettings || { warn "cinnamon: gsettings not found"; return 1; }
  gsettings list-schemas 2>/dev/null | grep -qx org.cinnamon.desktop.keybindings \
    || { warn "cinnamon: keybindings schema missing"; return 1; }
  local base=/org/cinnamon/desktop/keybindings/custom-keybindings/
  local sch=org.cinnamon.desktop.keybindings.custom-keybinding
  local item="" cmd name i expected
  expected="$(shell_quote "$BIN_ABS") --toggle"
  # Reuse a free slot or a slot that already invokes this exact app. Never
  # replace another custom command just because it mentions Screen AI.
  for i in $(seq 0 49); do
    item="custom$i"
    cmd="$(gsettings get "$sch:$base/$item/" command 2>/dev/null || true)"
    name="$(gsettings get "$sch:$base/$item/" name 2>/dev/null || true)"
    if [ "$cmd" = "''" ] || { [[ "$cmd" == *"$BIN_ABS"* ]] && [[ "$cmd" == *screen-ai* ]] && [[ "$name" == *"Screen AI"* ]]; }; then break; fi
    item=""
  done
  [ -n "$item" ] || { warn "cinnamon: no free custom-keybinding slot"; return 1; }
  gsettings set "$sch:$base/$item/" name "Screen AI" || return 1
  gsettings set "$sch:$base/$item/" command "$expected" || return 1
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
  local slots; slots="$(gsettings list-schemas 2>/dev/null | grep -oE 'org[.]mate[.]desktop[.]keybindings[.]custom[0-9]+')"
  [ -z "$slots" ] && { warn "mate: no custom-keybinding schemas found"; return 1; }
  local sch="" cmd name s expected
  expected="$(shell_quote "$BIN_ABS") --toggle"
  for s in $slots; do
    cmd="$(gsettings get "$s" action 2>/dev/null || true)"
    name="$(gsettings get "$s" name 2>/dev/null || true)"
    if [ "$cmd" = "''" ] || { [[ "$cmd" == *"$BIN_ABS"* ]] && [[ "$cmd" == *screen-ai* ]] && [[ "$name" == *"Screen AI"* ]]; }; then
      sch="$s"; break
    fi
  done
  [ -z "$sch" ] && { warn "mate: no free custom-keybinding slot"; return 1; }
  gsettings set "$sch" name "Screen AI" || return 1
  gsettings set "$sch" action "$expected" || return 1
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
  local kw="" plasver="" launch="$BIN_ABS --toggle" app_dir app_file existing="" wanted temp shortcut_cfg="$CFGXDG/kglobalshortcutsrc"
  local owned_before=0 clash="" register=1
  have kwriteconfig6 && kw=kwriteconfig6
  [ -z "$kw" ] && have kwriteconfig5 && kw=kwriteconfig5
  app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  mkdir -p "$app_dir"
  app_file="$(desktop_managed_path "$app_dir" screen-ai-toggle "Screen AI" "Exec=$BIN_ABS")"
  if [ -f "$app_file" ] && { grep -Fq 'X-ScreenAI-Managed=true' "$app_file" || { grep -qxF 'Name=Screen AI' "$app_file" && grep -Fq "Exec=$BIN_ABS" "$app_file"; }; }; then
    owned_before=1
  fi
  safe_to_edit "$app_file" || { warn "plasma: refusing to overwrite a symlinked or read-only desktop entry: $app_file"; return 1; }

  # Direct global-shortcut activation is version-sensitive. Keep any existing
  # foreign entry/binding intact and give a clear System Settings fallback.
  if [ -e "$shortcut_cfg" ] && ! safe_to_edit "$shortcut_cfg"; then
    warn "plasma: kglobalshortcutsrc is symlinked or read-only; leaving it unchanged"
    register=0
  elif [ -f "$shortcut_cfg" ]; then
    clash="$(grep -F "$KDE_KEY" "$shortcut_cfg" | grep -v 'screen-ai-toggle[.]desktop' | head -n1)"
    existing="$(grep -F -A5 '[services][screen-ai-toggle.desktop]' "$shortcut_cfg" | grep '^_launch=' | head -n1 | cut -d= -f2- || true)"
  fi
  if [ -n "$clash" ]; then
    warn "plasma: $KDE_KEY is already assigned elsewhere; left the binding unchanged"
    register=0
  elif [ -n "$existing" ] && [ "$owned_before" -ne 1 ]; then
    warn "plasma: a shortcut entry already exists; left it unchanged for safety"
    register=0
  elif [ -z "$kw" ]; then
    register=0
  fi

  temp="$(mktemp "$app_dir/.screen-ai.XXXXXX")" || return 1
  cat >"$temp" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI
Comment=Ask AI about your screen (managed by the Screen AI installer)
Exec=$(desktop_quote "$BIN_ABS") --toggle
Icon=screen-ai
Terminal=false
Categories=Utility;
NoDisplay=true
StartupWMClass=screen-ai
X-KDE-GlobalAccel-CommandShortcut=true
X-ScreenAI-Managed=true
EOF
  chmod 644 "$temp"; mv -f "$temp" "$app_file"
  receipt_set PLASMA_DESKTOP "$app_file"

  if [ "$register" -eq 1 ]; then
    plasver="$(plasmashell --version 2>/dev/null | grep -oE '[0-9]+' | head -n1 || true)"
    # Plasma 6 stores a bare accelerator; Plasma 5 uses the legacy tuple.
    if [ -z "$plasver" ]; then
      register=0
      warn "plasma: could not determine the Plasma version; shortcut will need manual setup"
    elif [ "$plasver" -ge 6 ]; then wanted="$KDE_KEY"
    else wanted="$KDE_KEY,$KDE_KEY,Screen AI"; fi
    if [ "$register" -eq 1 ] && { ! "$kw" --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _k_friendly_name "Screen AI" || \
       ! "$kw" --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _launch "$wanted"; }; then
      register=0
      warn "plasma: could not register the shortcut automatically"
    elif [ "$register" -eq 1 ]; then
      receipt_set PLASMA_SHORTCUT_VALUE "$wanted"
    fi
  fi
  if [ "$register" -eq 1 ]; then
    restart_kglobalaccel || warn "plasma: could not refresh the shortcut daemon; log out/in once"
    ok "plasma: $KDE_KEY → toggle (verify in System Settings → Shortcuts)"
    return 0
  fi
  warn "plasma: add Screen AI in System Settings → Shortcuts"
  note "command: $(shell_quote "$BIN_ABS") --toggle"
  return 1
}

bind_xfce() {
  have xfconf-query || { warn "xfce: xfconf-query not found"; return 1; }
  local expected old_key old_path old_value new_path current
  expected="$(shell_quote "$BIN_ABS") --toggle"
  old_key="$(receipt_get XFCE_KEY)"
  if [ -n "$old_key" ] && [ "$old_key" != "$XFCE_KEY" ]; then
    old_path="/commands/custom/$old_key"
    old_value="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$old_path" 2>/dev/null || true)"
    if [[ "$old_value" == *"$BIN_ABS"* ]] && [[ "$old_value" == *screen-ai* ]]; then
      xfconf-query -c xfce4-keyboard-shortcuts -p "$old_path" -r 2>/dev/null || true
    fi
  fi
  new_path="/commands/custom/$XFCE_KEY"
  current="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$new_path" 2>/dev/null || true)"
  if [ -n "$current" ] && { [[ "$current" != *"$BIN_ABS"* ]] || [[ "$current" != *screen-ai* ]]; }; then
    warn "xfce: $XFCE_KEY is already assigned; left the existing command unchanged"
    return 1
  fi
  if [ -n "$current" ]; then
    xfconf-query -c xfce4-keyboard-shortcuts -p "$new_path" -s "$expected" || return 1
  else
    xfconf-query -c xfce4-keyboard-shortcuts -p "$new_path" -n -t string -s "$expected" || return 1
  fi
  receipt_set XFCE_KEY "$XFCE_KEY"
  ok "xfce: $XFCE_KEY → toggle"
}

write_autostart() {
  local dir="$CFGXDG/autostart" file temp
  mkdir -p "$dir"
  file="$(desktop_managed_path "$dir" screen-ai "Screen AI" "Exec=$BIN_ABS")"
  safe_to_edit "$file" || { warn "autostart: refusing to overwrite an unmanaged or symlinked file: $file"; return 1; }
  temp="$(mktemp "$dir/.screen-ai.XXXXXX")" || return 1
  cat >"$temp" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI
Comment=Keep the Screen AI tray available in this desktop session
Exec=$(desktop_quote "$BIN_ABS")
Icon=screen-ai
Terminal=false
Categories=Utility;
NoDisplay=true
StartupWMClass=screen-ai
X-GNOME-Autostart-enabled=true
X-ScreenAI-Managed=true
EOF
  chmod 644 "$temp"; mv -f "$temp" "$file"
  receipt_set AUTOSTART "$file"
}

desktop_entry() {
  local dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications" app settings temp
  mkdir -p "$dir"
  app="$(desktop_managed_path "$dir" screen-ai "Screen AI" "Exec=$BIN_ABS")"
  settings="$(desktop_managed_path "$dir" screen-ai-settings "Screen AI Settings" "Exec=$BIN_ABS")"
  safe_to_edit "$app" || { warn "desktop entry is symlinked or read-only; left it untouched: $app"; return 1; }
  safe_to_edit "$settings" || { warn "settings desktop entry is symlinked or read-only; left it untouched: $settings"; return 1; }
  temp="$(mktemp "$dir/.screen-ai.XXXXXX")" || return 1
  cat >"$temp" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI
Comment=Ask AI about your screen
Exec=$(desktop_quote "$BIN_ABS") --toggle
Icon=screen-ai
Terminal=false
Categories=Utility;
StartupWMClass=screen-ai
X-ScreenAI-Managed=true
EOF
  chmod 644 "$temp"; mv -f "$temp" "$app"
  temp="$(mktemp "$dir/.screen-ai.XXXXXX")" || return 1
  cat >"$temp" <<EOF
[Desktop Entry]
Type=Application
Name=Screen AI Settings
Comment=Configure Screen AI providers and hotkeys
Exec=$(desktop_quote "$BIN_ABS") --settings
Icon=screen-ai
Terminal=false
Categories=Utility;Settings;
StartupWMClass=screen-ai
X-ScreenAI-Managed=true
EOF
  chmod 644 "$temp"; mv -f "$temp" "$settings"
  receipt_set APP_DESKTOP "$app"
  receipt_set SETTINGS_DESKTOP "$settings"
}

install_icon() {
  local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  local png_dir="$data_home/icons/hicolor/512x512/apps"
  local svg_dir="$data_home/icons/hicolor/scalable/apps"
  mkdir -p "$png_dir" "$svg_dir"
  local png_src="" svg_src="" tmp="" png_path="$png_dir/screen-ai.png" svg_path="$svg_dir/screen-ai.svg"
  local old_png old_svg old_png_sha old_svg_sha current_sha installed_any=0
  old_png="$(receipt_get ICON_PNG)"; old_svg="$(receipt_get ICON_SVG)"
  old_png_sha="$(receipt_get ICON_PNG_SHA)"; old_svg_sha="$(receipt_get ICON_SVG_SHA)"
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

  if [ -n "$png_src" ]; then
    current_sha=""
    [ ! -f "$png_path" ] || current_sha="$(sha256sum "$png_path" 2>/dev/null | awk '{print $1}')"
    if { [ ! -e "$png_path" ] || { [ "$old_png" = "$png_path" ] && [ -n "$old_png_sha" ] && [ "$current_sha" = "$old_png_sha" ]; }; } && safe_to_edit "$png_path"; then
      local png_tmp; png_tmp="$(mktemp "$png_dir/.screen-ai.XXXXXX")" || return 1
      if install -m 644 "$png_src" "$png_tmp" && mv -f "$png_tmp" "$png_path"; then
        receipt_set ICON_PNG "$png_path"
        receipt_set ICON_PNG_SHA "$(sha256sum "$png_path" | awk '{print $1}')"
        installed_any=1
      else rm -f "$png_tmp"; fi
    else
      warn "left an existing, unowned or symlinked PNG icon untouched: $png_path"
    fi
  fi
  if [ -n "$svg_src" ]; then
    current_sha=""
    [ ! -f "$svg_path" ] || current_sha="$(sha256sum "$svg_path" 2>/dev/null | awk '{print $1}')"
    if { [ ! -e "$svg_path" ] || { [ "$old_svg" = "$svg_path" ] && [ -n "$old_svg_sha" ] && [ "$current_sha" = "$old_svg_sha" ]; }; } && safe_to_edit "$svg_path"; then
      local svg_tmp; svg_tmp="$(mktemp "$svg_dir/.screen-ai.XXXXXX")" || return 1
      if install -m 644 "$svg_src" "$svg_tmp" && mv -f "$svg_tmp" "$svg_path"; then
        receipt_set ICON_SVG "$svg_path"
        receipt_set ICON_SVG_SHA "$(sha256sum "$svg_path" | awk '{print $1}')"
        installed_any=1
      else rm -f "$svg_tmp"; fi
    else
      warn "left an existing, unowned or symlinked SVG icon untouched: $svg_path"
    fi
  fi
  if [ "$installed_any" -eq 1 ]; then
    ok "installed available app icons"
  elif [ -n "$png_src" ] || [ -n "$svg_src" ]; then
    note "kept existing app icons that are not owned by this installer"
    have gtk-update-icon-cache && gtk-update-icon-cache -q "$data_home/icons/hicolor" 2>/dev/null || true
  else
    note "couldn't fetch the app icon (cosmetic only)"
  fi
  [ -n "$tmp" ] && rm -rf "$tmp"
  return 0
}

# Configure only the compositor or desktop that owns the current session. Dormant
# configs can be symlinked, generated, or intentionally prepared for another OS.
detect_targets() {
  case "$WM" in
    niri|hyprland|sway|i3|river|plasma|gnome|cinnamon|mate|xfce) TARGETS="$WM" ;;
    *) TARGETS="" ;;
  esac
}

remove_legacy_xdg_autostart() {
  local file="$CFGXDG/autostart/screen-ai.desktop"
  [ -f "$file" ] || return 0
  if grep -qxF 'Name=Screen AI' "$file" && \
     { grep -Fq "Exec=$BIN_ABS" "$file" || grep -Fq "Exec=$(desktop_quote "$BIN_ABS")" "$file"; } && \
     { grep -Fq 'X-ScreenAI-Managed=true' "$file" || grep -Fq "Exec=$BIN_ABS" "$file" || grep -Fq "Exec=$(desktop_quote "$BIN_ABS")" "$file"; }; then
    if safe_to_edit "$file"; then rm -f "$file"; note "removed an older generic autostart entry to avoid a duplicate compositor start"
    else warn "old Screen AI autostart is symlinked/read-only; check it to avoid duplicate startup"; fi
  fi
}

install_session_startup() {
  case "$WM" in
    plasma|gnome|cinnamon|mate|xfce)
      write_autostart && note "installed one XDG autostart entry for this desktop session"
      ;;
    # Supported compositors add startup beside their shortcut in one managed
    # module/drop-in. Never add a second XDG entry for those sessions.
    niri|hyprland|sway|i3|river) : ;;
    *) : ;;
  esac
}

print_manual_keys() {
  case "$WM" in
    labwc) note "labwc: add a <keybind> to ~/.config/labwc/rc.xml running: $BIN_ABS --toggle" ;;
    wayfire) note "wayfire: Wayfire Config Manager → Commands → bind a key to: $BIN_ABS --toggle" ;;
    *) warn "unknown compositor ($WM) — bind a key to this command by hand: $BIN_ABS --toggle" ;;
  esac
}

setup_startup_only() {
  SHORTCUT_ENABLED=0
  detect_targets
  local configured=0
  case "$WM" in
    niri) bind_niri && configured=1 ;;
    hyprland) bind_hyprland && configured=1 ;;
    sway) bind_sway && configured=1 ;;
    i3) bind_i3 && configured=1 ;;
    river) bind_river && configured=1 ;;
    plasma|gnome|cinnamon|mate|xfce)
      install_session_startup
      configured=1
      ;;
    *)
      if [ "$SESSION" = x11 ]; then
        note "no external shortcut added; the app's X11 fallback shortcuts remain available"
      else
        note "no shortcut or autostart was configured for this session"
      fi
      ;;
  esac
  if [ "$configured" -eq 1 ]; then
    case "$WM" in
      niri|hyprland|sway|i3|river)
        receipt_set TARGETS "$WM"
        remove_legacy_xdg_autostart
        ;;
    esac
  fi
  receipt_set SHORTCUT none
  SHORTCUT_ENABLED=1
}

setup_keybinding() {
  local keys=("Super+Shift+s" "Super+Shift+Space" "Ctrl+Alt+p" "Alt+Space" "Skip (no shortcut)")
  local sel
  choose "Pick a global shortcut" "${keys[@]}"
  sel="$CHOICE"
  if [ "$sel" -ge $((${#keys[@]} - 1)) ]; then
    note "skipped global shortcut; keeping session autostart where supported"
    setup_startup_only
    return 0
  fi
  sel="${keys[$sel]}"
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
  case " $done_ " in *" $WM "*)
    case "$WM" in niri|hyprland|sway|i3|river) remove_legacy_xdg_autostart ;; esac
    ;;
  esac
  install_session_startup
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
  local runtime_list missing
  runtime_list="$(runtime_pkgs)"
  if [ -z "$PM" ] || [ -z "$runtime_list" ]; then
    warn "runtime package names are unknown for this package manager; install GTK/WebKitGTK and screenshot tools manually"
  fi
  # Intentional word splitting: package names are space-delimited by each map.
  # shellcheck disable=SC2086
  missing="$(filter_installed $runtime_list)"
  if [ -z "$runtime_list" ]; then
    note "skipping automatic runtime package installation; verify screenshot, GTK and WebKitGTK dependencies manually"
  elif [ -z "$missing" ]; then
    ok "all runtime dependencies already satisfied ($PM)"
  elif [ "$NO_DEPS" -eq 1 ]; then
    note "skipped (--no-deps)"
  elif confirm "Install missing libraries ($missing)?" y; then
    install_deps "$missing"
  else
    note "skipped"
  fi

  step "Installing Screen AI"
  receipt_set BIN_DIR "$BIN_DIR"
  pkill -x screen-ai 2>/dev/null; sleep 0.3
  get_binary
  ok "installed → $BIN_DIR/screen-ai"
  install_update_tool || warn "source updater could not be installed"
  install_uninstaller || warn "uninstaller could not be installed"
  case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not in your PATH — add it to your shell profile" ;; esac

  mkdir -p "$SHARE_DIR"
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

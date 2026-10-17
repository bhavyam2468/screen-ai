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

# Self-update: installed copies are snapshots — fetch the latest uninstaller so
# its fixes apply, then re-exec it (once; guarded by SCREEN_AI_NO_SELF_UPDATE).
SELF_UPDATE_URL="https://raw.githubusercontent.com/bhavyam2468/screen-ai/main/uninstall.sh"
if [ -z "${SCREEN_AI_NO_SELF_UPDATE:-}" ] && command -v curl >/dev/null 2>&1; then
  _self="$0"; case "$_self" in */*) ;; *) _self="$(command -v "$_self" 2>/dev/null || true)" ;; esac
  if [ -n "$_self" ] && [ -f "$_self" ]; then
    _tmp="$(mktemp -t screen-ai-uninstall.XXXXXX 2>/dev/null || true)"
    if [ -n "$_tmp" ] && curl -fsSL --max-time 10 "$SELF_UPDATE_URL" -o "$_tmp" 2>/dev/null \
        && [ -s "$_tmp" ] && ! cmp -s "$_tmp" "$_self" 2>/dev/null; then
      chmod +x "$_tmp"
      export SCREEN_AI_NO_SELF_UPDATE=1
      exec bash "$_tmp" "$@"
    fi
    rm -f "$_tmp"
  fi
  unset _self _tmp
fi

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
# rescue the install receipt before wiping SHARE_DIR (drives shortcut cleanup below)
RECEIPT_TMP="$(mktemp -t screen-ai-receipt.XXXXXX 2>/dev/null || true)"
[ -n "$RECEIPT_TMP" ] && [ -f "$SHARE_DIR/receipt" ] && cp -p "$SHARE_DIR/receipt" "$RECEIPT_TMP" 2>/dev/null || true
rm -rf "$SHARE_DIR"
rm -f "$HOME/.local/share/applications/screen-ai.desktop"
rm -f "$HOME/.local/share/applications/screen-ai-settings.desktop"
rm -f "$HOME/.local/share/applications/screen-ai-toggle.desktop"
rm -f "$HOME/.config/autostart/screen-ai.desktop"
rm -f "$HOME/.local/share/icons/hicolor/512x512/apps/screen-ai.png" "$HOME/.local/share/icons/hicolor/scalable/apps/screen-ai.svg"
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
ok "removed binaries & desktop entries"

step "Cleaning compositor shortcuts & autostart"

# The installer records every change in $SHARE_DIR/receipt (rescued above into
# $RECEIPT_TMP before SHARE_DIR was wiped). Slots/keys we can't find there are
# re-discovered by scanning for our own command — never by blind pattern wipes.
RECEIPT="${RECEIPT_TMP:-$SHARE_DIR/receipt}"
CFGXDG="${XDG_CONFIG_HOME:-$HOME/.config}"
receipt_get() { grep "^$1=" "$RECEIPT" 2>/dev/null | tail -n1 | cut -d= -f2-; }
cfg_niri() { for c in "${NIRI_CONFIG:-}" "$CFGXDG/niri/config.kdl" "$HOME/.config/niri/config.kdl"; do [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return 0; }; done; return 1; }
cfg_hypr() { for c in "$CFGXDG/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf"; do [ -f "$c" ] && { printf '%s' "$c"; return 0; }; done; return 1; }
cfg_sway() { for c in "$CFGXDG/sway/config" "$HOME/.sway/config"; do [ -f "$c" ] && { printf '%s' "$c"; return 0; }; done; return 1; }
cfg_i3() { for c in "$HOME/.config/i3/config" "$HOME/.i3/config"; do [ -f "$c" ] && { printf '%s' "$c"; return 0; }; done; return 1; }

# Niri — delete only our include line, drop the drop-in, re-validate.
if cfg="$(cfg_niri)" && grep -q 'screen-ai[.]kdl' "$cfg" 2>/dev/null; then
  sed -i '/screen-ai[.]kdl/d' "$cfg"
  rm -f "$(dirname "$cfg")/screen-ai.kdl"
  if command -v niri >/dev/null 2>&1; then
    if niri validate -c "$cfg" >/dev/null 2>&1; then ok "niri keybind removed (config valid)"
    else warn "niri keybind removed, but 'niri validate' reports errors — check your config"; fi
  else ok "niri keybind removed"; fi
fi

# Hyprland / Sway — same pattern, then live reload.
if cfg="$(cfg_hypr)" && grep -q 'screen-ai[.]conf' "$cfg" 2>/dev/null; then
  sed -i '/screen-ai[.]conf/d' "$cfg"
  rm -f "$(dirname "$cfg")/screen-ai.conf"
  command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1
  ok "hyprland keybind removed"
fi
if cfg="$(cfg_sway)" && grep -q 'screen-ai[.]conf' "$cfg" 2>/dev/null; then
  sed -i '/screen-ai[.]conf/d' "$cfg"
  rm -f "$(dirname "$cfg")/screen-ai.conf"
  command -v swaymsg >/dev/null 2>&1 && swaymsg reload >/dev/null 2>&1
  ok "sway keybind removed"
fi

# i3 — drop-in (current installers) plus the inline block (older installers).
if cfg="$(cfg_i3)"; then
  if grep -q 'screen-ai[.]conf' "$cfg" 2>/dev/null || grep -q 'screen-ai BEGIN' "$cfg" 2>/dev/null; then
    sed -i '/screen-ai[.]conf/d' "$cfg"
    rm -f "$(dirname "$cfg")/screen-ai.conf"
    grep -q 'screen-ai BEGIN' "$cfg" 2>/dev/null && sed -i '/# screen-ai BEGIN/,/# screen-ai END/d' "$cfg"
    if command -v i3 >/dev/null 2>&1; then
      i3 -C -c "$cfg" >/dev/null 2>&1 || warn "i3 config has errors (left over or yours) — check with 'i3 -C'"
    fi
    command -v i3-msg >/dev/null 2>&1 && i3-msg reload >/dev/null 2>&1
    ok "i3 keybind removed"
  fi
fi

# River — our init lines carry a trailing marker; delete exactly those.
if [ -f "$CFGXDG/river/init" ] && grep -q '# screen-ai' "$CFGXDG/river/init" 2>/dev/null; then
  sed -i '/# screen-ai/d' "$CFGXDG/river/init"
  ok "river keybind removed (takes effect next login)"
fi

# GNOME — exact list surgery (python3), then wipe our settings path.
if command -v gsettings >/dev/null 2>&1; then
  cur="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || true)"
  if [[ "$cur" == *screen-ai* ]]; then
    if command -v python3 >/dev/null 2>&1; then
      new="$(cur="$cur" python3 -c "import ast,os; l=ast.literal_eval(os.environ['cur']); print([x for x in l if 'screen-ai' not in x])" 2>/dev/null || true)"
      [ -n "$new" ] && gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new" 2>/dev/null
    else
      warn "gnome: python3 missing — remove the now-empty Screen AI entry in Settings → Keyboard"
    fi
    gsettings reset-recursively org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/screen-ai/ 2>/dev/null
    ok "gnome shortcut removed"
  fi
fi

# Cinnamon — receipt slot plus a self-healing scan (our slots only), then
# rebuild custom-list from slots that still have a command (keep __dummy__).
if command -v gsettings >/dev/null 2>&1 && gsettings list-schemas 2>/dev/null | grep -qx org.cinnamon.desktop.keybindings; then
  cbase=/org/cinnamon/desktop/keybindings/custom-keybindings/
  csch=org.cinnamon.desktop.keybindings.custom-keybinding
  cslot="$(receipt_get CINNAMON_SLOT)"
  cremoved=0
  if [ -n "$cslot" ]; then gsettings reset-recursively "$csch:$cbase/$cslot/" 2>/dev/null && cremoved=1; fi
  for i in $(seq 0 49); do
    cmd="$(gsettings get "$csch:$cbase/custom$i/" command 2>/dev/null)" || continue
    if [[ "$cmd" == *screen-ai* ]]; then gsettings reset-recursively "$csch:$cbase/custom$i/" 2>/dev/null; cremoved=1; fi
  done
  if [ "$cremoved" = 1 ]; then
    cur="$(gsettings get org.cinnamon.desktop.keybindings custom-list 2>/dev/null)"
    keep=""
    for n in $(printf '%s' "$cur" | tr -d '[]' | tr ',' ' ' | tr -d "' "); do
      [ -z "$n" ] && continue
      if [ "$n" = "__dummy__" ]; then keep="$keep, '$n'"; continue; fi
      c="$(gsettings get "$csch:$cbase/$n/" command 2>/dev/null)"
      if [ -n "$c" ] && [ "$c" != "''" ]; then keep="$keep, '$n'"; fi
    done
    keep="[${keep#, }]"
    gsettings set org.cinnamon.desktop.keybindings custom-list "$keep" 2>/dev/null
    ok "cinnamon shortcut removed"
  fi
fi

# MATE — receipt slot plus scan; reset owned slots to schema defaults.
if command -v gsettings >/dev/null 2>&1; then
  mslot="$(receipt_get MATE_SLOT)"
  mremoved=0
  mslots="$(gsettings list-schemas 2>/dev/null | grep -oE 'org[.]mate[.]desktop[.]keybindings[.]custom[0-9]+')"
  for sch in $mslots; do
    cmd="$(gsettings get "$sch" action 2>/dev/null)" || continue
    if [[ "$cmd" == *screen-ai* ]] || [ "${sch##*.}" = "$mslot" ]; then
      gsettings reset "$sch" name 2>/dev/null
      gsettings reset "$sch" action 2>/dev/null
      gsettings reset "$sch" binding 2>/dev/null
      mremoved=1
    fi
  done
  [ "$mremoved" = 1 ] && ok "mate shortcut removed"
fi

# Plasma — delete only our two keys, then refresh the daemon.
kw=""
command -v kwriteconfig6 >/dev/null 2>&1 && kw=kwriteconfig6
[ -z "$kw" ] && command -v kwriteconfig5 >/dev/null 2>&1 && kw=kwriteconfig5
if [ -n "$kw" ] && grep -q 'screen-ai-toggle' "$HOME/.config/kglobalshortcutsrc" 2>/dev/null; then
  "$kw" --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _launch --delete 2>/dev/null
  "$kw" --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _k_friendly_name --delete 2>/dev/null
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user try-restart plasma-kglobalaccel.service >/dev/null 2>&1 || true
  elif command -v killall >/dev/null 2>&1; then
    killall kglobalacceld kglobalaccel5 >/dev/null 2>&1; sleep 0.5
    for d in /usr/lib/kglobalacceld /usr/libexec/kglobalacceld /usr/lib/kglobalaccel5 /usr/libexec/kglobalaccel5; do
      if [ -x "$d" ]; then (nohup "$d" >/dev/null 2>&1 &); break; fi
    done
  fi
  ok "plasma shortcut removed (log out/in if it lingers)"
fi

# XFCE — receipt key plus a self-healing scan of custom commands.
if command -v xfconf-query >/dev/null 2>&1; then
  xremoved=0
  xk="$(receipt_get XFCE_KEY)"
  if [ -n "$xk" ]; then xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$xk" -r 2>/dev/null && xremoved=1; fi
  xprops="$(xfconf-query -c xfce4-keyboard-shortcuts -l -p /commands/custom 2>/dev/null)"
  for prop in $xprops; do
    v="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" 2>/dev/null)" || continue
    if [[ "$v" == *screen-ai* ]]; then xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r 2>/dev/null; xremoved=1; fi
  done
  [ "$xremoved" = 1 ] && ok "xfce shortcut removed"
fi

[ -n "${RECEIPT_TMP:-}" ] && rm -f "$RECEIPT_TMP"

step "Configuration files"
if [ "$PURGE" -eq 1 ] || confirm "Delete configuration & API keys in $CFG_DIR?" n; then
  rm -rf "$CFG_DIR"
  ok "removed $CFG_DIR"
else
  note "kept $CFG_DIR (your API keys and preferences are preserved)"
fi

printf '\n  %s\n\n' "$(gradient "Screen AI uninstalled successfully.")"
note "config backups (*.screen-ai-bak) were left in place — delete them once everything works"

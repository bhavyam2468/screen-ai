#!/usr/bin/env bash
# Screen AI — safe uninstaller. Managed drop-ins are removed; user configs and
# saved provider settings are preserved unless --purge is explicitly requested.
set -u

BIN_DIR="${SCREEN_AI_BIN_DIR:-$HOME/.local/bin}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CFGXDG="${XDG_CONFIG_HOME:-$HOME/.config}"
SHARE_DIR="$DATA_HOME/screen-ai"
CFG_DIR="$CFGXDG/screen-ai"
RECEIPT="$SHARE_DIR/receipt"
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
if [ -t 1 ]; then
  RED=$'\e[38;2;244;63;94m'; GRN=$'\e[38;2;74;222;128m'; AMB=$'\e[38;2;251;191;36m'; CYN=$'\e[38;2;0;210;255m'; RST=$'\e[0m'; DIM=$'\e[2m'
else
  RED=''; GRN=''; AMB=''; CYN=''; RST=''; DIM=''
fi
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '  %s!%s %s\n' "$AMB" "$RST" "$1"; }
note() { printf '    %s%s%s\n' "$DIM" "$1" "$RST"; }
step() { printf '\n  %s%s%s\n' "$CYN" "$1" "$RST"; }

confirm() {
  local question="$1" default="${2:-y}" answer
  if [ "$HAS_TTY" -eq 0 ] || [ "$ASSUME_YES" -eq 1 ]; then [ "$default" = y ]; return; fi
  printf '  %s?%s %s %s[%s]%s ' "$CYN" "$RST" "$question" "$DIM" "$([ "$default" = y ] && echo Y/n || echo y/N)" "$RST" >/dev/tty
  read -r answer </dev/tty || answer=""
  answer="${answer:-$default}"
  case "$answer" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

safe_to_edit() {
  local path="$1" walk="$1"
  case "$walk" in /*) ;; *) walk="$PWD/$walk" ;; esac
  while [ "$walk" != / ]; do
    [ ! -L "$walk" ] || return 1
    walk="$(dirname "$walk")"
  done
  [ -f "$path" ] && [ -w "$path" ]
}

receipt_get() {
  [ -f "$RECEIPT" ] || return 0
  awk -v key="$1" 'index($0, key "=") == 1 { value=substr($0, length(key)+2) } END { print value }' "$RECEIPT"
}
if [ -z "${SCREEN_AI_BIN_DIR:-}" ]; then
  recorded_bin="$(receipt_get BIN_DIR)"
  [ -n "$recorded_bin" ] && BIN_DIR="$recorded_bin"
fi

desktop_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//%/%%}"
  printf '"%s"' "$value"
}

remove_exact_line() {
  local file="$1" line="$2" temp
  [ -f "$file" ] || return 0
  safe_to_edit "$file" || { warn "left symlinked/read-only config untouched: $file"; return 1; }
  temp="$(mktemp "$(dirname "$file")/.screen-ai-uninstall.XXXXXX")" || return 1
  grep -vxF "$line" "$file" >"$temp" || true
  cat "$temp" >"$file"
  rm -f "$temp"
}

remove_marked_lines() {
  local file="$1" marker="$2" temp
  [ -f "$file" ] || return 0
  safe_to_edit "$file" || { warn "left symlinked/read-only config untouched: $file"; return 1; }
  temp="$(mktemp "$(dirname "$file")/.screen-ai-uninstall.XXXXXX")" || return 1
  awk -v marker="$marker" 'index($0, marker) == 0 { print }' "$file" >"$temp"
  cat "$temp" >"$file"
  rm -f "$temp"
}

remove_receipted_file() {
  local path_key="$1" sha_key="$2" file expected actual
  file="$(receipt_get "$path_key")"
  expected="$(receipt_get "$sha_key")"
  [ -n "$file" ] && [ -f "$file" ] && [ -n "$expected" ] || return 0
  safe_to_edit "$file" || { warn "left symlinked/read-only app asset untouched: $file"; return 1; }
  actual="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"
  if [ "$actual" = "$expected" ]; then rm -f "$file"; else note "kept app asset modified since installation: $file"; fi
}

remove_managed_file() {
  local file="$1" marker="$2"
  [ -n "$file" ] && [ -f "$file" ] || return 0
  safe_to_edit "$file" || { warn "left symlinked/read-only managed path untouched: $file"; return 1; }
  grep -Fq "$marker" "$file" 2>/dev/null || return 0
  rm -f "$file"
}

remove_managed_dropin() {
  local file="$1"
  [ -n "$file" ] && [ -f "$file" ] || return 0
  if grep -Fqi 'managed by the Screen AI installer' "$file"; then
    safe_to_edit "$file" || { warn "left symlinked/read-only compositor drop-in untouched: $file"; return 1; }
    rm -f "$file"
  fi
}

remove_entry() {
  local file="$1" name="$2" exec_prefix="$3" quoted_exec
  [ -n "$file" ] && [ -f "$file" ] || return 1
  quoted_exec="$(desktop_quote "$exec_prefix")"
  if grep -qxF "Name=$name" "$file" 2>/dev/null && \
     { grep -Fq "Exec=$exec_prefix" "$file" || grep -Fq "Exec=$quoted_exec" "$file"; } && \
     { grep -Fq 'X-ScreenAI-Managed=true' "$file" || grep -Fq "Exec=$exec_prefix" "$file" || grep -Fq "Exec=$quoted_exec" "$file"; }; then
    safe_to_edit "$file" || { warn "left symlinked/read-only desktop entry untouched: $file"; return 1; }
    rm -f "$file"
    return 0
  fi
  return 1
}

printf '\n  %s\n' "Screen AI — Uninstall"
if ! confirm "Uninstall Screen AI from this system?" y; then echo "Aborted."; exit 0; fi

step "Stopping Screen AI"
if command -v pgrep >/dev/null 2>&1 && pgrep -x screen-ai >/dev/null 2>&1; then
  command -v pkill >/dev/null 2>&1 && pkill -x screen-ai 2>/dev/null || true
  sleep 0.3
  ok "stopped running instances"
else
  note "no active process found"
fi

step "Removing managed compositor integration"
# New installers record exact active config paths/include lines. Only these
# marked entries and drop-ins are removed; backup files are retained for undo.
for kind in NIRI HYPR SWAY I3; do
  cfg="$(receipt_get "${kind}_CONFIG")"
  drop="$(receipt_get "${kind}_DROPIN")"
  include="$(receipt_get "${kind}_INCLUDE")"
  if [ -n "$cfg" ] && [ -f "$cfg" ] && [ -n "$include" ]; then
    remove_exact_line "$cfg" "$include"
  fi
  remove_managed_dropin "$drop"
done

# Clean older versions' fixed-name drop-ins only when their contents carry the
# installer's marker, and only remove their matching include lines.
niri_cfg="$(receipt_get NIRI_CONFIG)"
[ -n "$niri_cfg" ] || niri_cfg="${NIRI_CONFIG:-$CFGXDG/niri/config.kdl}"
old_niri="$(dirname "$niri_cfg")/screen-ai.kdl"
if [ -f "$old_niri" ] && grep -Fqi 'managed by the Screen AI installer' "$old_niri"; then
  remove_exact_line "$niri_cfg" 'include "screen-ai.kdl" // screen-ai'
  remove_managed_dropin "$old_niri"
fi

# Previous Hyprland/Sway/i3 installers used a fixed screen-ai.conf drop-in.
for pair in "hypr:$CFGXDG/hypr/hyprland.conf" "sway:$CFGXDG/sway/config" "i3:$HOME/.config/i3/config"; do
  kind="${pair%%:*}"; cfg="${pair#*:}"; old="$(dirname "$cfg")/screen-ai.conf"
  if [ -f "$old" ] && grep -Fqi 'managed by the Screen AI installer' "$old"; then
    remove_marked_lines "$cfg" '# screen-ai'
    remove_marked_lines "$cfg" ' # screen-ai'
    remove_managed_dropin "$old"
  fi
done
# Also support i3's older inline managed block.
i3cfg="$(receipt_get I3_CONFIG)"
[ -n "$i3cfg" ] || i3cfg="$HOME/.config/i3/config"
if [ -f "$i3cfg" ] && grep -q 'screen-ai BEGIN' "$i3cfg"; then
  if safe_to_edit "$i3cfg"; then sed -i '/# screen-ai BEGIN/,/# screen-ai END/d' "$i3cfg"; fi
fi

# River writes marked shell lines rather than supporting a common include.
river_init="$(receipt_get RIVER_INIT)"
[ -n "$river_init" ] || river_init="$CFGXDG/river/init"
if [ -f "$river_init" ]; then
  river_bind="$(receipt_get RIVER_BIND)"; river_start="$(receipt_get RIVER_START)"
  [ -n "$river_bind" ] && remove_exact_line "$river_init" "$river_bind"
  [ -n "$river_start" ] && remove_exact_line "$river_init" "$river_start"
  # Legacy River entries had a trailing # screen-ai marker.
  remove_marked_lines "$river_init" '# screen-ai'
fi
command -v niri >/dev/null 2>&1 && [ -n "$niri_cfg" ] && [ -f "$niri_cfg" ] && niri validate -c "$niri_cfg" >/dev/null 2>&1 || true
command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
command -v swaymsg >/dev/null 2>&1 && swaymsg reload >/dev/null 2>&1 || true
command -v i3-msg >/dev/null 2>&1 && i3-msg reload >/dev/null 2>&1 || true
ok "managed compositor entries removed (user config backups retained)"

step "Removing desktop shortcuts and autostart"
plasma_desktop="$(receipt_get PLASMA_DESKTOP)"
if [ -z "$plasma_desktop" ]; then plasma_desktop="$DATA_HOME/applications/screen-ai-toggle.desktop"; fi
plasma_shortcut_value="$(receipt_get PLASMA_SHORTCUT_VALUE)"

remove_entry "$(receipt_get APP_DESKTOP)" "Screen AI" "$BIN_DIR/screen-ai" || true
remove_entry "$(receipt_get SETTINGS_DESKTOP)" "Screen AI Settings" "$BIN_DIR/screen-ai" || true
remove_entry "$DATA_HOME/applications/screen-ai.desktop" "Screen AI" "$BIN_DIR/screen-ai" || true
remove_entry "$DATA_HOME/applications/screen-ai-settings.desktop" "Screen AI Settings" "$BIN_DIR/screen-ai" || true
remove_entry "$plasma_desktop" "Screen AI" "$BIN_DIR/screen-ai" || true

remove_entry "$(receipt_get AUTOSTART)" "Screen AI" "$BIN_DIR/screen-ai" || true
remove_entry "$CFGXDG/autostart/screen-ai.desktop" "Screen AI" "$BIN_DIR/screen-ai" || true

if [ -n "$plasma_shortcut_value" ]; then
  kw=""; kr=""
  command -v kwriteconfig6 >/dev/null 2>&1 && kw=kwriteconfig6
  [ -n "$kw" ] || { command -v kwriteconfig5 >/dev/null 2>&1 && kw=kwriteconfig5; }
  command -v kreadconfig6 >/dev/null 2>&1 && kr=kreadconfig6
  [ -n "$kr" ] || { command -v kreadconfig5 >/dev/null 2>&1 && kr=kreadconfig5; }
  if [ -n "$kw" ] && [ -n "$kr" ] && safe_to_edit "$CFGXDG/kglobalshortcutsrc"; then
    current="$("$kr" --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _launch 2>/dev/null || true)"
    if [ "$current" = "$plasma_shortcut_value" ]; then
      "$kw" --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _launch --delete 2>/dev/null || true
      friendly="$("$kr" --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _k_friendly_name 2>/dev/null || true)"
      [ "$friendly" = "Screen AI" ] && "$kw" --file kglobalshortcutsrc --group services --group screen-ai-toggle.desktop --key _k_friendly_name --delete 2>/dev/null || true
      command -v systemctl >/dev/null 2>&1 && systemctl --user try-restart plasma-kglobalaccel.service >/dev/null 2>&1 || true
    else
      note "kept the Plasma shortcut because its current assignment no longer matches the installer receipt"
    fi
  else
    warn "could not verify the Plasma shortcut; remove it manually in System Settings → Shortcuts if needed"
  fi
fi

remove_receipted_file ICON_PNG ICON_PNG_SHA || true
remove_receipted_file ICON_SVG ICON_SVG_SHA || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q "$DATA_HOME/icons/hicolor" 2>/dev/null || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true

step "Removing desktop keybindings"
if command -v gsettings >/dev/null 2>&1; then
  gnome_path="$(receipt_get GNOME_PATH)"
  [ -n "$gnome_path" ] || gnome_path=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/screen-ai/
  gnome_schema_root=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding
  gnome_command="$(gsettings get "$gnome_schema_root:$gnome_path" command 2>/dev/null || true)"
  if [[ "$gnome_command" == *"$BIN_DIR/screen-ai"* ]] && [[ "$gnome_command" == *screen-ai* ]]; then
    current="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || true)"
    if [[ "$current" == *"$gnome_path"* ]] && command -v python3 >/dev/null 2>&1; then
      cleaned="$(CURRENT="$current" REMOVE_PATH="$gnome_path" python3 -c "import ast,os; print([p for p in ast.literal_eval(os.environ['CURRENT']) if p != os.environ['REMOVE_PATH']])" 2>/dev/null || true)"
      [ -n "$cleaned" ] && gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$cleaned" 2>/dev/null || true
      gsettings reset-recursively "$gnome_schema_root:$gnome_path" 2>/dev/null || true
    fi
  fi

  if gsettings list-schemas 2>/dev/null | grep -qx org.cinnamon.desktop.keybindings; then
    cbase=/org/cinnamon/desktop/keybindings/custom-keybindings/
    csch=org.cinnamon.desktop.keybindings.custom-keybinding
    cslot="$(receipt_get CINNAMON_SLOT)"
    if [ -n "$cslot" ]; then
      command_value="$(gsettings get "$csch:$cbase/$cslot/" command 2>/dev/null || true)"
      name="$(gsettings get "$csch:$cbase/$cslot/" name 2>/dev/null || true)"
      if [[ "$command_value" == *"$BIN_DIR/screen-ai"* ]] && [[ "$command_value" == *screen-ai* ]] && [[ "$name" == *"Screen AI"* ]]; then
        gsettings reset-recursively "$csch:$cbase/$cslot/" 2>/dev/null || true
        cur="$(gsettings get org.cinnamon.desktop.keybindings custom-list 2>/dev/null || true)"
        if [[ "$cur" == *"'$cslot'"* ]]; then
          keep=()
          while IFS= read -r item; do
            [ -n "$item" ] && [ "$item" != "$cslot" ] && keep+=("$item")
          done < <(printf '%s' "$cur" | tr -d "[]'" | tr ',' '\n' | tr -d ' ')
          if ((${#keep[@]})); then
            list="['$(IFS="', '"; echo "${keep[*]}")']"
          else
            list="[]"
          fi
          gsettings set org.cinnamon.desktop.keybindings custom-list "$list" 2>/dev/null || true
        fi
      fi
    fi
  fi

  mslot="$(receipt_get MATE_SLOT)"
  if [ -n "$mslot" ]; then
    mschema="org.mate.desktop.keybindings.$mslot"
    if gsettings list-schemas 2>/dev/null | grep -qx "$mschema"; then
      command_value="$(gsettings get "$mschema" action 2>/dev/null || true)"
      name="$(gsettings get "$mschema" name 2>/dev/null || true)"
      if [[ "$command_value" == *"$BIN_DIR/screen-ai"* ]] && [[ "$command_value" == *screen-ai* ]] && [[ "$name" == *"Screen AI"* ]]; then
        gsettings reset "$mschema" name 2>/dev/null || true
        gsettings reset "$mschema" action 2>/dev/null || true
        gsettings reset "$mschema" binding 2>/dev/null || true
      fi
    fi
  fi
fi

if command -v xfconf-query >/dev/null 2>&1; then
  xkey="$(receipt_get XFCE_KEY)"
  if [ -n "$xkey" ]; then
    xpath="/commands/custom/$xkey"
    command_value="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$xpath" 2>/dev/null || true)"
    if [[ "$command_value" == *"$BIN_DIR/screen-ai"* ]] && [[ "$command_value" == *screen-ai* ]]; then
      xfconf-query -c xfce4-keyboard-shortcuts -p "$xpath" -r 2>/dev/null || true
    fi
  fi
fi

step "Removing theming hooks"
# install.sh registers a Matugen template that writes $CFG_DIR/colors.conf. Left
# behind, Matugen would keep writing into a directory this uninstaller removes.
matugen_config="$CFGXDG/matugen/config.toml"
if [ -f "$matugen_config" ] && grep -q '^\[templates\.screen-ai\]' "$matugen_config"; then
  if safe_to_edit "$matugen_config"; then
    # Guarded: an empty $temp would truncate the user's Matugen config.
    if temp="$(mktemp "$(dirname "$matugen_config")/.screen-ai-uninstall.XXXXXX")" && [ -n "$temp" ]; then
      # Drop the table header and its keys, up to the next table or end of file.
      awk '/^\[templates\.screen-ai\][[:space:]]*$/ { skip = 1; next }
           skip && /^\[/ { skip = 0 }
           !skip { print }' "$matugen_config" >"$temp"
      cat "$temp" >"$matugen_config"
      rm -f "$temp"
      ok "removed the Screen AI template from $matugen_config"
    else
      warn "could not create a temporary file next to $matugen_config; template left in place"
    fi
  else
    warn "left symlinked/read-only Matugen config untouched: $matugen_config"
  fi
fi
rm -f "$CFGXDG/matugen/templates/screen-ai-colors.conf"
rm -f "$CFGXDG/dms-shell/matugen/configs/screen-ai.toml"
rm -f "$CFGXDG/dms-shell/matugen/templates/screen-ai-colors.conf"
note "Matugen itself is untouched; only Screen AI's template was removed"

step "Removing installed files"
updater="$(receipt_get UPDATER_WRAPPER)"
[ -n "$updater" ] || updater="$BIN_DIR/screen-ai-update"
remove_managed_file "$updater" 'screen-ai managed wrapper'
uninstaller="$(receipt_get UNINSTALL_WRAPPER)"
[ -n "$uninstaller" ] || uninstaller="$BIN_DIR/screen-ai-uninstall"
remove_managed_file "$uninstaller" 'screen-ai managed wrapper'
[ -f "$BIN_DIR/screen-ai-uninstall" ] && [ -L "$BIN_DIR/screen-ai-uninstall" ] && \
  [ "$(readlink "$BIN_DIR/screen-ai-uninstall" 2>/dev/null || true)" = "$SHARE_DIR/uninstall.sh" ] && rm -f "$BIN_DIR/screen-ai-uninstall"
[ -f "$BIN_DIR/screen-ai-update" ] && [ -L "$BIN_DIR/screen-ai-update" ] && \
  [ "$(readlink "$BIN_DIR/screen-ai-update" 2>/dev/null || true)" = "$SHARE_DIR/update.sh" ] && rm -f "$BIN_DIR/screen-ai-update"
rm -f "$BIN_DIR/screen-ai"

if [ -d "$SHARE_DIR" ] && [ ! -L "$SHARE_DIR" ]; then rm -rf "$SHARE_DIR"; fi
ok "removed Screen AI binaries, updater and managed data"

step "Configuration files"
if [ "$PURGE" -eq 1 ] || confirm "Delete configuration and saved API keys in $CFG_DIR?" n; then
  rm -rf "$CFG_DIR"
  ok "removed $CFG_DIR"
else
  note "kept $CFG_DIR (your API keys and preferences are preserved)"
fi

printf '\n  %s\n\n' "Screen AI uninstalled successfully."
note "Compositor backups (*.screen-ai-bak) were left in place so your original configs remain recoverable."

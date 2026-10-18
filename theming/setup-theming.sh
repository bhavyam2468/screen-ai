#!/usr/bin/env bash
# Registers Screen AI's Matugen template, both for standalone Matugen and for
# DankMaterialShell (which relocates Matugen under ~/.config/dms-shell).
# Idempotent: an existing registration is left alone.
set -u

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/matugen/screen-ai-colors.conf"

[ -f "$TEMPLATE_FILE" ] || { echo "missing template: $TEMPLATE_FILE" >&2; exit 1; }
mkdir -p "$CONFIG/screen-ai"

# 1. Standalone Matugen ($XDG_CONFIG_HOME/matugen). Paths are written resolved,
#    so a custom XDG_CONFIG_HOME still lands where the overlay reads.
if command -v matugen >/dev/null 2>&1 || [ -d "$CONFIG/matugen" ]; then
  mkdir -p "$CONFIG/matugen/templates"
  cp "$TEMPLATE_FILE" "$CONFIG/matugen/templates/"
  matugen_config="$CONFIG/matugen/config.toml"
  [ -f "$matugen_config" ] || : >"$matugen_config"
  if ! grep -q '^\[templates\.screen-ai\]' "$matugen_config"; then
    {
      printf '\n[templates.screen-ai]\n'
      printf "input_path = '%s/matugen/templates/screen-ai-colors.conf'\n" "$CONFIG"
      printf "output_path = '%s/screen-ai/colors.conf'\n" "$CONFIG"
    } >>"$matugen_config"
    echo "registered the Screen AI template in $matugen_config"
  fi
fi

# 2. DankMaterialShell ($XDG_CONFIG_HOME/dms-shell/matugen). DMS substitutes
#    SHELL_DIR and CONFIG_DIR itself.
if [ -d "$CONFIG/dms-shell/matugen" ]; then
  mkdir -p "$CONFIG/dms-shell/matugen/templates" "$CONFIG/dms-shell/matugen/configs"
  cp "$TEMPLATE_FILE" "$CONFIG/dms-shell/matugen/templates/"
  cat >"$CONFIG/dms-shell/matugen/configs/screen-ai.toml" <<'DMS_EOF'
[templates.dmsscreenai]
input_path = 'SHELL_DIR/matugen/templates/screen-ai-colors.conf'
output_path = 'CONFIG_DIR/screen-ai/colors.conf'
DMS_EOF
  echo "registered the Screen AI template in $CONFIG/dms-shell/matugen/configs/screen-ai.toml"
fi

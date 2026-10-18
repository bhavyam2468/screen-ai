#!/usr/bin/env bash
# Sets up Screen AI Matugen templates across common desktop environments (DMS, standalone Matugen).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/matugen/screen-ai-colors.conf"
CONFIG_SNIPPET="$SCRIPT_DIR/matugen/config.toml.snippet"

mkdir -p "$HOME/.config/screen-ai"

# 1. Setup for Standalone Matugen (~/.config/matugen)
if command -v matugen &>/dev/null || [ -d "$HOME/.config/matugen" ]; then
    mkdir -p "$HOME/.config/matugen/templates"
    cp "$TEMPLATE_FILE" "$HOME/.config/matugen/templates/"
    if [ ! -f "$HOME/.config/matugen/config.toml" ]; then
        touch "$HOME/.config/matugen/config.toml"
    fi
    if ! grep -q "\[templates.screen-ai\]" "$HOME/.config/matugen/config.toml"; then
        echo "" >> "$HOME/.config/matugen/config.toml"
        cat "$CONFIG_SNIPPET" >> "$HOME/.config/matugen/config.toml"
        echo "Registered Screen AI template in ~/.config/matugen/config.toml"
    fi
fi

# 2. Setup for DankMaterialShell (~/.config/dms-shell/matugen)
if [ -d "$HOME/.config/dms-shell/matugen" ]; then
    mkdir -p "$HOME/.config/dms-shell/matugen/templates" "$HOME/.config/dms-shell/matugen/configs"
    cp "$TEMPLATE_FILE" "$HOME/.config/dms-shell/matugen/templates/"
    cat << 'DMS_EOF' > "$HOME/.config/dms-shell/matugen/configs/screen-ai.toml"
[templates.dmsscreenai]
input_path = 'SHELL_DIR/matugen/templates/screen-ai-colors.conf'
output_path = 'CONFIG_DIR/screen-ai/colors.conf'
DMS_EOF
    echo "Registered Screen AI template in ~/.config/dms-shell/matugen/configs/screen-ai.toml"
fi

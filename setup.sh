#!/usr/bin/env bash
# Shared install/update entry point. The installer synchronizes this checkout,
# installs missing dependencies, builds locally and replaces the installed app.
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$APP_DIR/install.sh" --from-source "$@"

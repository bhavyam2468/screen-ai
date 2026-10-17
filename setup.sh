#!/usr/bin/env bash
# Compatibility entry point for existing setup.sh instructions.
# The canonical installer detects the current session, installs dependencies,
# and builds Screen AI from this checkout when run from the repository.
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$APP_DIR/install.sh" --from-source "$@"

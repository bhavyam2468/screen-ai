#!/usr/bin/env bash
# Backward-compatible alias; all fetching, building and installing lives in setup.
set -euo pipefail
APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$APP_DIR/setup.sh" --yes --no-setup --no-bind --no-launch "$@"

#!/usr/bin/env bash
# Build Screen AI from the requested Git commit on this machine and atomically
# replace the installed executable. No compiled application is downloaded.
set -Eeuo pipefail

REPO="bhavyam2468/screen-ai"
REF="main"
INSTALL_PATH="${SCREEN_AI_INSTALL_PATH:-${HOME}/.local/bin/screen-ai}"

usage() {
  cat <<'EOF'
Usage: update.sh [--ref main|<40-character-commit>] [--install-path PATH]

Fetches Screen AI source, builds it locally, and atomically installs the binary.
The default source is the latest main branch. Settings and compositor configs
are not changed.
EOF
}

while (($#)); do
  case "$1" in
    --ref)
      (($# >= 2)) || { echo "--ref needs a value" >&2; exit 2; }
      REF="$2"; shift 2 ;;
    --install-path)
      (($# >= 2)) || { echo "--install-path needs a value" >&2; exit 2; }
      INSTALL_PATH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$REF" in
  main|stable) ;;
  *)
    [[ "$REF" =~ ^[0-9a-fA-F]{40}$ ]] || {
      echo "Refusing unsupported source ref '$REF' (expected main or a full commit SHA)." >&2
      exit 2
    }
    ;;
esac

for command in git node npm rustc cargo; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required build tool '$command' is missing. Re-run the Screen AI installer to install build dependencies." >&2
    exit 1
  }
done

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
[[ "$NODE_MAJOR" -ge 18 ]] || {
  echo "Node.js 18 or newer is required (found $(node --version 2>/dev/null || echo missing)). Re-run the installer after upgrading Node.js." >&2
  exit 1
}
version_at_least() {
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
RUST_VERSION="$(rustc --version 2>/dev/null | awk '{print $2}')"
[[ -n "$RUST_VERSION" ]] && version_at_least "$RUST_VERSION" 1.78.0 || {
  echo "Rust 1.78.0 or newer is required (found ${RUST_VERSION:-unknown}). Re-run the installer to set up rustup." >&2
  exit 1
}

mkdir -p "$(dirname "$INSTALL_PATH")"
[[ -w "$(dirname "$INSTALL_PATH")" ]] || {
  echo "Cannot write to install directory: $(dirname "$INSTALL_PATH")" >&2
  exit 1
}

WORK_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/screen-ai"
mkdir -p "$WORK_ROOT"
WORK_DIR="$(mktemp -d "$WORK_ROOT/source-build.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

printf 'Fetching Screen AI source (%s)…\n' "$REF"
git -C "$WORK_DIR" init --quiet
git -C "$WORK_DIR" remote add origin "https://github.com/${REPO}.git"
git -C "$WORK_DIR" fetch --quiet --depth 1 origin "$REF"
git -C "$WORK_DIR" checkout --quiet --detach FETCH_HEAD

if [[ "$REF" != main && "$REF" != stable ]]; then
  ACTUAL_SHA="$(git -C "$WORK_DIR" rev-parse HEAD)"
  [[ "${ACTUAL_SHA,,}" == "${REF,,}" ]] || {
    echo "Fetched commit does not match the requested revision." >&2
    exit 1
  }
fi

printf 'Installing JavaScript dependencies…\n'
(
  cd "$WORK_DIR"
  npm ci --no-audit --no-fund
  npm run build
)

printf 'Compiling the native app locally (this can take several minutes)…\n'
(
  cd "$WORK_DIR"
  cargo build --locked --release --manifest-path src-tauri/Cargo.toml
)
BUILT="$WORK_DIR/src-tauri/target/release/screen-ai"
[[ -x "$BUILT" ]] || { echo "Build completed without producing $BUILT" >&2; exit 1; }

STAGED="$(dirname "$INSTALL_PATH")/.screen-ai.new.$$"
trap 'rm -f "$STAGED"; cleanup' EXIT
install -m 755 "$BUILT" "$STAGED"
mv -f "$STAGED" "$INSTALL_PATH"
printf 'Installed the locally built app at %s\n' "$INSTALL_PATH"

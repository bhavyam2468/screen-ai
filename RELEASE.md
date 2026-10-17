# Source-first releases and updates

Screen AI is distributed as source. GitHub contains the application source and lockfiles; it does not build or publish a default Linux executable. Users compile the application locally through `install.sh`, `setup.sh`, or the in-app source updater.

## CI policy

`.github/workflows/continuous.yml` checks shell syntax, whitespace, tracked build output, and JavaScript lockfile installation. It deliberately does not run the frontend/native build, upload artifacts, or create rolling binary releases. Generated output such as `dist/` and `src-tauri/target/` must not be committed.

## Version identity

The local build embeds `v1.<short-sha>` (and a `+dirty` suffix when built from a modified checkout) in `src-tauri/build.rs`. Settings checks the public `main` commit and reports whether it differs from the installed revision.

## User update path

The installer places a source updater at `screen-ai-update` and the Settings panel invokes that helper. It fetches the `main` source, runs `npm ci`, builds the frontend and then runs a locked Cargo release build on the user’s machine. The completed executable is staged beside the install path and atomically renamed into place. Settings and compositor config are not changed. The app asks for a restart after success.

The helper can also be run directly:

```bash
screen-ai-update
# or, from a checkout:
bash ./install.sh
```

A source build requires Git, Node.js 18+, npm, Cargo/Rust, and the native GTK/WebKitGTK development libraries. The install script handles common package managers and gives manual instructions when it cannot identify a package map.

## Previous binary releases

Older rolling release assets may still exist on GitHub for historical reasons. The current installer and in-app updater do not discover or install those binaries; new updates are built from source locally. Do not restore a workflow that attaches compiled app executables to the default GitHub distribution path without changing this policy and the updater together.

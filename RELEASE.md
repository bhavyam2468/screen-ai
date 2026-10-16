# Cutting a release

Both the installer (`install.sh`) and the in-app updater expect the same
release layout. Follow these steps exactly.

## 1. Bump the version

`src-tauri/Cargo.toml` (`version = "x.y.z"`) and `package.json` must match.
The updater compares the release tag against `CARGO_PKG_VERSION` with semver.

## 2. Build the release binary

```bash
npm install
npm run build
cd src-tauri && cargo build --release
```

Sanity checks before packaging:

```bash
# gtk must resolve to ONE 0.18.x shared with wry/tao (see Cargo.toml note)
cargo tree -i gtk
```

## 3. Package the tarball

The tarball must contain exactly one entry — `screen-ai` at the root.
Anything else and both the installer and the updater will refuse it.

```bash
cd src-tauri/target/release
tar -czf screen-ai-x86_64-linux.tar.gz screen-ai
tar -tzf screen-ai-x86_64-linux.tar.gz   # must print exactly: screen-ai
```

## 4. Publish the checksum sidecar

```bash
sha256sum screen-ai-x86_64-linux.tar.gz > screen-ai-x86_64-linux.tar.gz.sha256
```

Upload **both** files as release assets. The updater looks for
`<tarball>.sha256` first, then falls back to `SHA256SUMS*` / `checksums*.txt`
assets, then to `<download-url>.sha256`. A present-but-mismatched checksum is a
hard install failure; a missing sidecar installs with a warning (back-compat
with old releases).

## 5. Tag + publish

```bash
# e.g. v0.2.0 — tags may carry a leading `v`, it is stripped for comparison
git tag v0.2.0 && git push origin v0.2.0
gh release create v0.2.0 \
  screen-ai-x86_64-linux.tar.gz \
  screen-ai-x86_64-linux.tar.gz.sha256 \
  --title "v0.2.0" --notes "…"
```

`install.sh` pulls `releases/latest/download/screen-ai-x86_64-linux.tar.gz`,
so keep that asset name stable. The release-notes body is shown in-app on the
update prompt — write it for end users, not just a changelog dump.

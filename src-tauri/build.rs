fn main() {
    // Build identity for git-based updates (see updater in main.rs).
    // Cargo.toml's version is scaffolding (major line "1"); the real version
    // is v1.<commit> assembled from these values at compile time.
    let sha = git(&["rev-parse", "--short=7", "HEAD"]).unwrap_or_else(|| "unknown".into());
    let dirty = std::process::Command::new("git")
        .args(["status", "--porcelain"])
        .output()
        .map(|o| !o.stdout.is_empty())
        .unwrap_or(false);
    println!("cargo:rustc-env=SCREEN_AI_COMMIT={sha}");
    println!(
        "cargo:rustc-env=SCREEN_AI_DIRTY={}",
        if dirty { "1" } else { "0" }
    );
    // Re-embed when the checkout moves (paths resolved from the package dir,
    // emitted only when present so non-Git source exports stay quiet).
    let manifest = std::env::var("CARGO_MANIFEST_DIR").unwrap_or_default();
    for rel in ["../.git/HEAD", "../.git/index"] {
        let p = std::path::Path::new(&manifest).join(rel);
        if p.exists() {
            println!("cargo:rerun-if-changed={}", p.display());
        }
    }
    tauri_build::build()
}

fn git(args: &[&str]) -> Option<String> {
    let out = std::process::Command::new("git").args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() {
        None
    } else {
        Some(s)
    }
}

# Updates: push-to-release

There is no manual release process. CI builds every push:

- push to `main` → builds → republishes the **`v1-continuous`** release (stable)
- push to any other branch → builds → republishes **`continuous-beta`** (prerelease)

## Versions

Versions are git-based: **`v1.<short-sha>`**, e.g. `v1.3716db4`. The commit SHA
plus its timestamp are embedded at compile time (see `src-tauri/build.rs`);
`Cargo.toml`'s `1.0.0` is scaffolding for the major line only. An update is
offered whenever a rolling release points at a strictly newer commit than the
running build.

## Changelog

The release notes are the built commit's subject + body, followed by a machine
footer the updater parses (invisible on GitHub, which renders it as a comment):

```
<subject>

<body>

<!-- screen-ai-build -->
sha: <full sha>
time: <unix commit time>
branch: <branch>
```

Write commit messages for end users — they show up in-app on the update card.

## Beta

A beta is offered only while its branch is genuinely ahead of `main` (checked
live via the compare API) and only when it is newer than both the running
build and stable. If several branches move, beta tracks the most recently
pushed one.

## Installers

`install.sh` pulls the stable tarball directly, bypassing "latest":

```
releases/download/v1-continuous/screen-ai-x86_64-linux.tar.gz (+ .sha256)
```

## Bootstrap note

The stable tag is deliberately named `v1-continuous`, not `continuous`:
pre-1.0 updaters normalize any `v1*` tag to `1.0.0`, which reads as newer than
`0.x` — so their last old-style update carries them onto this pipeline. Do
not rename the tag.

## If CI is red

Failed builds publish nothing; the updater keeps offering the last good one.
Check the Actions tab, fix forward, push again.

# Yukino Akane Mod Notes

## Purpose

This workspace rebuilds the installed Codex Desktop Windows package into a separate Yukino-branded MSIX. The intent is to keep Yukino isolated from the official `OpenAI.Codex` package while preserving Codex Desktop behavior.

## Observed Layout

- `build-yukino.ps1`: main rebuild script.
- `verify-yukino.ps1`: post-build and installed-package verification script.
- `src_unpacked/`: copied and patched source package tree. Generated, ignored.
- `logs/`: timestamped ASAR extraction/repack work directories and smoke logs. Generated, ignored.
- `out/`: MSIX, certificate, and unpack verification output. Generated, ignored.

At the time this note was written, generated data under this workspace was about 12 GB:

- `out/`: can grow to multiple gigabytes because it contains MSIX packages and unpack verification output.
- `logs/`: can grow to multiple gigabytes because each build keeps an extracted ASAR work directory.
- `src_unpacked/`: about 1 GB for a copied desktop package tree.

## Build Flow

`build-yukino.ps1` performs these high-level steps:

1. Resolve the latest installed `OpenAI.Codex` AppX package.
2. Copy the installed package into `src_unpacked/`.
3. Remove old AppX metadata and signatures.
4. Patch `AppxManifest.xml` to use `yukino.akane`, `Yukino`, `CN=Yukino`, and the `yukino://` protocol.
5. Rename `app\Codex.exe` to `app\Yukino.exe`.
6. Extract `app\resources\app.asar`.
7. Patch JavaScript, webview assets, package metadata, loose resources, and text branding.
8. Run `node --check` over patched build JavaScript.
9. Repack `app.asar`, preserving unpacked native modules for `better-sqlite3` and `node-pty`.
10. Launch once to capture Electron ASAR integrity output, then patch the executable hash when needed.
11. Smoke launch the patched source tree.
12. Pack and sign the MSIX with Windows SDK tools.
13. Unpack the MSIX for structure verification.
14. Optionally install and run `verify-yukino.ps1`.

## Release Flow

`scripts\Publish-YukinoRelease.ps1` turns the latest built MSIX into a private GitHub release:

1. Resolve the latest `out\yukino.akane_*_x64.msix`, `out\Yukino.cer`, and `scripts\Install-YukinoRelease.ps1`.
2. Copy the installer into `out\`.
3. Recompute `out\SHA256SUMS.txt` from the MSIX so stale checksums cannot be uploaded.
4. Generate release notes under `out\release-notes-<tag>.md` unless an explicit notes path is provided.
5. Run `verify-yukino.ps1`; publishing stops if verification fails.
6. In dry-run mode, print the assets without touching GitHub.
7. Outside dry-run mode, call `gh release create` with the MSIX, certificate, checksum file, and installer.

## Patch Inventory

Branding and identity:

- Replaces visible `Codex` branding with `Yukino`.
- Replaces package identity `OpenAI.Codex` / `com.openai.codex` with `yukino.akane`.
- Replaces `codex://` with `yukino://`.
- Replaces common `.codex` user-facing paths with `.yukino`.
- Sets default `CODEX_HOME` to `%USERPROFILE%\.yukino` inside the bootstrap path when not already set.
- Mirrors `YUKINO_HOME` to `CODEX_HOME`.

Updater isolation:

- Patches the desktop bootstrap path so the Sparkle updater reports unavailable and does not check or install official updates.

Feature and settings patches:

- Filters unsupported experimental feature sync entries from webview entry assets.
- Disables the ChatGPT-only API-key gate in `gradient-*.js` webview assets.
- Enables the desktop plugins settings entry in `settings-page-*.js`.
- Rewrites Agent Settings config writes from `write-config-value` to `batch-write-config-value` with reload enabled.

Runtime and packaging:

- Keeps native module unpack rules for `node_modules/better-sqlite3` and `node_modules/node-pty`.
- Patches Electron ASAR integrity hash in the renamed executable when Electron reports a mismatch.

## Latest Verified State

Verification command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-yukino.ps1
```

Latest observed result:

- `latest-build`: PASS, `logs\build-20260502-142726`.
- `agent-settings-write-patch`: PASS.
- `plugin-auth-gate`: PASS.
- `plugins-settings-entry`: PASS.
- `installed-package`: PASS, `yukino.akane_26.429.3425.1_x64__fnxqm6pztzbs0`.
- `installed-agent-settings-patch`: PASS.
- `installed-plugin-auth-gate`: PASS.
- `latest-msix`: PASS, `out\yukino.akane_26.429.3425.1_x64.msix`.
- `config-approval-policy`: PASS, `approval_policy=never`.
- `config-sandbox-mode`: PASS, `sandbox_mode=danger-full-access`.
- `windows-sandbox-compat`: PASS, `[windows] sandbox` compatibility value present.
- `config-feature-plugins`: PASS.
- `config-browser-use-plugin`: PASS.
- `latest-batch-write-log`: WARN when no recent config write occurred.
- `recent-config-conflicts`: PASS.

Sandbox compatibility note:

- Keep the `[windows] sandbox` value for current desktop compatibility until the runtime no longer requires it. The active top-level `sandbox_mode` is also valid.

## Useful Commands

Build without installing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-yukino.ps1
```

Build and install:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-yukino.ps1 -Install
```

Verify current build and installed package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-yukino.ps1
```

Prepare release assets without publishing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Publish-YukinoRelease.ps1 -Tag v<version>-yukino.<n> -DryRun
```

Publish a private GitHub release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Publish-YukinoRelease.ps1 -Tag v<version>-yukino.<n> -Title "Yukino Codex <version>-yukino.<n>" -Latest
```

Check installed source and target packages:

```powershell
Get-AppxPackage -Name OpenAI.Codex
Get-AppxPackage -Name yukino.akane
```

## Follow-Ups

- Keep the `[windows] sandbox` value in `%USERPROFILE%\.yukino\config.toml` for current desktop compatibility until the runtime no longer requires it.
- Consider adding a small release checklist whenever a new official Codex version becomes the source package.
- Consider factoring brittle minified-asset patch patterns into named tests or probes so upstream asset changes fail with clearer messages.

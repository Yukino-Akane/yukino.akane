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

- `out/`: about 6.1 GB.
- `logs/`: about 4.2 GB.
- `src_unpacked/`: about 1.1 GB.

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

- `latest-build`: PASS, `logs\build-20260501-220708`.
- `agent-settings-write-patch`: PASS.
- `plugin-auth-gate`: PASS.
- `plugins-settings-entry`: PASS.
- `installed-package`: PASS, `yukino.akane_26.429.2026.1_x64__fnxqm6pztzbs0`.
- `installed-agent-settings-patch`: PASS.
- `latest-msix`: PASS, `out\yukino.akane_26.429.2026.1_x64.msix`.
- `config-approval-policy`: PASS, `approval_policy=never`.
- `config-sandbox-mode`: PASS, `sandbox_mode=danger-full-access`.
- `config-feature-plugins`: PASS.
- `config-browser-use-plugin`: PASS.
- `latest-batch-write-log`: PASS.
- `recent-config-conflicts`: PASS, historical conflicts only.

Known warning:

- `legacy-windows-sandbox`: WARN. The config still contains a legacy `[windows] sandbox` value, although the active top-level `sandbox_mode` is valid.

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

Check installed source and target packages:

```powershell
Get-AppxPackage -Name OpenAI.Codex
Get-AppxPackage -Name yukino.akane
```

## Follow-Ups

- Decide whether to clean the legacy `[windows] sandbox` value from `%USERPROFILE%\.yukino\config.toml`.
- Consider adding a small release checklist whenever a new official Codex version becomes the source package.
- Consider factoring brittle minified-asset patch patterns into named tests or probes so upstream asset changes fail with clearer messages.

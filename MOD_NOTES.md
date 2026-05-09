# Yukino Akane Mod Notes

## Purpose

This workspace rebuilds the installed Codex Desktop Windows package into a separate Yukino-branded MSIX. The intent is to keep Yukino isolated from the official `OpenAI.Codex` package while preserving Codex Desktop behavior.

## Observed Layout

- `build-yukino.ps1`: main rebuild script.
- `verify-yukino.ps1`: post-build and installed-package verification script.
- `package.json`: npm command surface for tests, build, verification, and release commands.
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
3. Write `logs\build-*\source-manifest.json` from the copied official source package.
4. Remove old AppX metadata and signatures.
5. Patch `AppxManifest.xml` to use `yukino.akane`, `Yukino`, `CN=Yukino`, and the `yukino://` protocol.
6. Rename `app\Codex.exe` to `app\Yukino.exe`.
7. Extract `app\resources\app.asar`.
8. Patch JavaScript, webview assets, package metadata, loose resources, and text branding.
9. Run `node --check` over patched build JavaScript.
10. Repack `app.asar`, preserving unpacked native modules for `better-sqlite3` and `node-pty`.
11. Launch once to capture Electron ASAR integrity output, then patch the executable hash when needed.
12. Smoke launch the patched source tree.
13. Pack and sign the MSIX with Windows SDK tools.
14. Unpack the MSIX for structure verification.
15. Write `logs\build-*\build-audit.json` to compare source and output changes against an allowlist.
16. Record build metadata under `%USERPROFILE%\.yukino\build-history.jsonl`.
17. Optionally install and run `verify-yukino.ps1`.

## Release Flow

`scripts\Publish-YukinoRelease.ps1` turns the latest built MSIX into a private GitHub release:

1. Resolve the latest `out\yukino.akane_*_x64.msix`, `out\Yukino.cer`, and `scripts\Install-YukinoRelease.ps1`.
2. Copy the installer into `out\`.
3. Recompute `out\SHA256SUMS.txt` from the MSIX so stale checksums cannot be uploaded.
4. Generate release notes under `out\release-notes-<tag>.md` unless an explicit notes path is provided.
5. Run `verify-yukino.ps1`; publishing stops if verification fails.
6. Run `scripts\Test-YukinoReleaseSafety.ps1`; publishing stops if the repo is not private, tracked files contain credential/config paths or high-confidence key patterns, tracked files mention CPA skill identifiers, or the MSIX contains CPA-related paths.
7. In dry-run mode, print the assets without touching GitHub.
8. Outside dry-run mode, call `gh release create` with the MSIX, certificate, checksum file, and installer.
9. Record published release metadata under `%USERPROFILE%\.yukino\release-history.jsonl`.
10. After publishing, run `scripts\Test-YukinoReleaseInstall.ps1 -Tag <tag>` when the user has approved reinstalling Yukino. This downloads the private release assets into a temp directory, verifies `SHA256SUMS.txt`, runs the published installer, runs `verify-yukino.ps1`, performs a launch smoke, and runs `scripts\Test-YukinoPostInstallBrowserSmoke.ps1`.

Verification runs also append `%USERPROFILE%\.yukino\verify-history.jsonl`.

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
- Disables the ChatGPT-only API-key gate in `gradient-*.js`, `skills-page-*.js`, and current `app-main-*.js` webview assets.
- Patches the combined sidebar Plugins/Skills click route so the desktop `Plugins` label opens `/plugins` with `initialMode=browse` and `initialTab=plugins`, avoiding the shared page's default Skills tab.
- Enables the desktop plugins settings entry in `settings-page-*.js`.
- Rewrites Agent Settings config writes from `write-config-value` to `batch-write-config-value` with reload enabled.
- Adds quiet Yukino version and local diagnostics rows inside Agent Settings > Workspace Dependencies. The version row copies the Yukino package/release/config-home identity, and the diagnostics row runs the bundled read-only `scripts\Test-YukinoLocalState.ps1 -NoRepair` through the fixed `run-yukino-local-diagnostics` app-server method, then copies the bounded report. It keeps `npm run diagnose` as a fallback hint and does not add a standalone diagnostics page or arbitrary UI-provided command runner.
- Supports the current `app-main-*.css` bundle for the Yukino sidebar background patch.

Runtime and packaging:

- Keeps native module unpack rules for `node_modules/better-sqlite3` and `node_modules/node-pty`.
- Replaces both AppX image assets and the PE icon resources embedded in `app\Yukino.exe`.
- Patches Electron ASAR integrity hash in the renamed executable when Electron reports a mismatch.
- Preserves the bundled Chrome plugin's public native host name `com.openai.codexextension` so the Chrome Web Store extension can connect to Yukino's `extension-host.exe`.

## Patch Contracts

Plugin auth gate:

- In current `skills-page-*.js` bundles, the Plugins page auth-block check is anchored near `pluginsAuthBlockedToast.title`.
- Older bundles used the concrete shape `s&&!m`; newer minified bundles may rename the same entry gate, for example `o&&!p`.
- The intended Yukino patch is `enabled&&!gate` -> `enabled&&!0` (`s&&!0`, `o&&!0`, etc.), which keeps the Plugins marketplace entry enabled while bypassing the API-key guard.
- Do not patch this shape to `s&&!1`; that makes the page-entry condition permanently false and leaves the sidebar Plugins flow stuck on the Skills surface.
- `tests\Test-YukinoPluginAuthGatePatch.ps1` and `verify-yukino.ps1` must continue to require the patched `&&!0` entry gate and reject both stale gated forms and `s&&!1` in latest build assets and installed `app.asar`.
- Installed verification must extract `app.asar` and inspect the real `webview\assets\*.js` files. Do not blindly scan the binary `app.asar`, because unrelated bundles can contain the same minified token shapes and produce false positives.

Sidebar Plugins route:

- In current `app-main-*.js` bundles, the sidebar Plugins and Skills entries can share a minified click handler and shared page surface.
- The Plugins branch must navigate to `/plugins` with ``state:{initialMode:`browse`,initialTab:`plugins`}`` so the shared page opens the Plugins tab instead of defaulting back to Skills.
- `tests\Test-YukinoPluginAuthGatePatch.ps1` and `verify-yukino.ps1` must continue to require that stateful Plugins route in both latest build assets and installed `app.asar`.

Settings plugins entry:

- Older settings bundles gated `plugins-settings` behind an extension/electron condition; newer bundles expose `plugins-settings` and `skills-settings` directly in the settings section map.
- `verify-yukino.ps1` must accept the direct section-map form as PASS and still fail if the old extension-only plugins settings entry remains.

Config log warnings:

- `errorCode=-32600` is not by itself a config conflict. Current app logs can emit that code for unrelated methods such as `experimentalFeature/enablement/set` and `thread/goal/get`.
- Treat config log conflicts as relevant only when the method is `config/...`, the line mentions `configVersionConflict`, or the line says `Unable to save`.
- Missing `config/batchWrite` evidence in recent logs is informational after a clean install or launch-only smoke; run a manual settings write when validating the Agent Settings write patch.

Chrome plugin native host:

- The current public Chrome Web Store extension expects native host name `com.openai.codexextension`.
- Do not rename the bundled Chrome plugin native host to `yukino.akaneextension` unless Yukino ships a separate Chrome extension ID.
- `build-yukino.ps1` must run `Patch-ChromeNativeHostCompatibility` after loose plugin resource branding so `scripts\extension-id.json` and `scripts\installManifest.mjs` keep `com.openai.codexextension`.
- `verify-yukino.ps1` and `scripts\Test-YukinoLocalState.ps1` must check the bundled Chrome plugin cache, installed user cache, and `HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension` manifest target.
- Short-term model: Yukino and official Codex share the public extension/native-host name, with the registry manifest pointing to Yukino's cache. Full isolation requires a Yukino-specific Chrome extension.
- `scripts\Repair-YukinoChromePluginCache.ps1` must recover from Windows file locks by building a complete recovery cache directory, retargeting `chrome\latest`, and recording locked stale paths in `chrome\pending-delete.jsonl` for delayed cleanup. Do not make repair success depend on deleting the locked old cache synchronously.

## Latest Verified State

Verification command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-yukino.ps1
```

Latest observed result:

- `latest-build`: PASS, `logs\build-20260509-212203`.
- `chrome-plugin-build-cache`: PASS after `logs\build-20260509-212203`.
- `agent-settings-write-patch`: PASS.
- `settings-local-diagnostics-entry`: PASS, hidden inside Agent Settings maintenance.
- `settings-yukino-version-entry`: PASS, hidden inside Agent Settings maintenance.
- `plugin-auth-gate`: PASS.
- `sidebar-plugin-route`: PASS.
- `plugins-settings-entry`: PASS.
- `installed-package`: PASS, `yukino.akane_26.506.3741.1_x64__fnxqm6pztzbs0`.
- `installed-executable-icon`: PASS.
- `installed-agent-settings-patch`: PASS.
- `installed-plugin-auth-gate`: PASS.
- `installed-sidebar-plugin-route`: PASS.
- `installed-sidebar-background-patch`: PASS.
- `latest-msix`: PASS, `out\yukino.akane_26.506.3741.1_x64.msix`.
- `config-approval-policy`: PASS, `approval_policy=never`.
- `config-sandbox-mode`: PASS, `sandbox_mode=danger-full-access`.
- `windows-sandbox-compat`: PASS, `[windows] sandbox` compatibility value present.
- `config-feature-plugins`: PASS.
- `config-browser-use-plugin`: PASS.
- `config-chrome-plugin`: PASS.
- `installed-chrome-plugin-cache`: PASS after repairing missing `.codex-plugin` and `assets` under `%USERPROFILE%\.yukino\plugins\cache\openai-bundled\chrome\0.1.7`.
- `chrome-native-host-yukino-target`: PASS, `com.openai.codexextension.json` points to `%USERPROFILE%\.yukino\plugins\cache\openai-bundled\chrome\latest\extension-host\windows\x64\extension-host.exe`.
- `latest-batch-write-log`: PASS when no recent `config/batchWrite` evidence exists; the detail asks for a manual settings write when validating that patch.
- `recent-config-conflicts`: PASS when recent `-32600` lines are unrelated to `config/...` methods.
- `chrome-plugin-cache-pending-cleanup`: PASS when no delayed cleanup manifest remains under `%USERPROFILE%\.yukino\plugins\cache\openai-bundled\chrome\pending-delete.jsonl`.
- `plugin_cache_windows_file_lock`: PASS when lock evidence is historical/recovered, `latest` is complete, no pending cleanup entries remain, and the native host manifest targets Yukino. Treat it as WARN only when paired with an incomplete `latest` cache, pending cleanup entries, or a bad native host target.
- `post-install-browser-smoke`: PASS; current installed Yukino has a Yukino-path app-server process, Browser runtime pipe log, Yukino `node_repl.exe`, enabled Chrome extension, native host manifest targeting Yukino's cache, and a non-disruptive `about:blank` Chrome dry-run. When a manual Browser GUI smoke has just run, `scripts\Test-YukinoPostInstallBrowserSmoke.ps1 -RequireBrowserRuntimeActivity` also requires matched `IAB_LIFECYCLE` Browser turn start/end log lines with the same `turnId`.

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

Run the release safety gate directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-YukinoReleaseSafety.ps1
```

Run a private release install smoke after publishing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-YukinoReleaseInstall.ps1 -Tag v<version>-yukino.<n>
```

Verify a just-completed manual Browser GUI smoke without reinstalling:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-YukinoPostInstallBrowserSmoke.ps1 -MinLogTime (Get-Date).AddMinutes(-10) -RequireBrowserRuntimeActivity
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

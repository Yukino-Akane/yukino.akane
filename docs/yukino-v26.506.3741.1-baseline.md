# Yukino 26.506.3741.1 Baseline

This document records the stable Yukino baseline after the 2026-05-09 release hardening pass.

## Baseline

- Release tag: `v26.506.3741.1-yukino.2`
- Release page: `https://github.com/Yukino-Akane/yukino.akane/releases/tag/v26.506.3741.1-yukino.2`
- Published at: `2026-05-09T10:21:20Z`
- Published package: `yukino.akane_26.506.3741.1_x64.msix`
- MSIX SHA256: `DF2AC60E928AF817FE3E67415281150F033FE4D5E09A539E80DCD64D8701FC23`
- Installed package: `yukino.akane_26.506.3741.1_x64__fnxqm6pztzbs0`
- Current maintenance HEAD after diagnostic cleanup: `0c9231c chore: quiet recovered Chrome plugin cache lock diagnostics`

The release assets remain valid. Later maintenance commits through `0c9231c` improve diagnostics, Browser smoke verification, and repair logic; they do not require republishing the MSIX by themselves.

## What Was Stabilized

- Restored Yukino branding and executable icon verification after the app icon fell back to the official default icon.
- Fixed the sidebar Plugins route so it opens `/plugins` with `initialMode=browse` and `initialTab=plugins`, instead of falling back to Skills.
- Fixed the Plugins marketplace entry by requiring the patched entry gate to stay enabled as `&&!0`; the bad `&&!1` form disables the Plugins page.
- Added a private-release safety gate that rejects a non-private repo, tracked credential/config paths, high-confidence key/token patterns, CPA skill identifiers, and CPA-related paths inside the MSIX.
- Confirmed the CPA skill was not included in the repo or release assets.
- Added a real release install smoke script: `scripts\Test-YukinoReleaseInstall.ps1`.
- Added a read-only local diagnostic script: `scripts\Test-YukinoLocalState.ps1`.
- Added strict post-install Browser smoke evidence for manual GUI checks: `scripts\Test-YukinoPostInstallBrowserSmoke.ps1 -RequireBrowserRuntimeActivity` now requires matched Browser turn start/end log lines with the same `turnId`.
- Recovered locked Chrome plugin cache updates by retargeting a complete recovery cache and deferring locked stale-path cleanup.
- Cleaned verification noise so `verify-yukino.ps1` reports real risks instead of upstream-shape or unrelated-log false warnings.

## Verification Evidence

Use these commands for this baseline:

```powershell
npm test
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-yukino.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-YukinoLocalState.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-YukinoPostInstallBrowserSmoke.ps1 -MinLogTime (Get-Date).AddMinutes(-10) -RequireBrowserRuntimeActivity
git diff --check
```

Latest expected result:

- `npm test`: PASS.
- `verify-yukino.ps1`: PASS, with historical/recovered Chrome plugin cache lock evidence reported as PASS only when the cache is complete, no pending cleanup entries remain, and the native host target is correct.
- `scripts\Test-YukinoLocalState.ps1`: PASS on a clean pushed worktree, including recovered Chrome plugin cache lock evidence and matched Browser runtime activity evidence when recent logs contain it.
- `scripts\Test-YukinoPostInstallBrowserSmoke.ps1 -RequireBrowserRuntimeActivity`: PASS after a manual Yukino Browser GUI task, requiring matched Browser turn log lines by `turnId`.
- `git diff --check`: PASS.
- Manual GUI smoke: passed by user confirmation.
- Release install smoke: passed from downloaded private release assets; SHA matched the published checksum, installer completed, installed package verification passed, and Yukino launched.

Run the release install smoke after future releases when the user has approved reinstalling Yukino:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-YukinoReleaseInstall.ps1 -Tag v<version>-yukino.<n>
```

## Lessons For The Next Update

- Always compare fragile minified webview patches against the locally installed official `OpenAI.Codex` package before changing patch logic.
- For the Plugins page, keep the entry condition enabled while bypassing the auth guard. `s&&!0` or its renamed equivalent is correct; `s&&!1` is a regression.
- Installed verification must extract `app.asar` and inspect real `webview\assets\*.js` files. Binary scans can produce false positives.
- `errorCode=-32600` in logs is not necessarily a config conflict. Treat it as config-relevant only for `method=config/...`, `configVersionConflict`, or `Unable to save`.
- Missing recent `config/batchWrite` evidence after launch-only smoke is not a release warning. Validate the Agent Settings write path with a deliberate manual settings write.
- Browser runtime cannot be forced from a standalone Node process because `browser-client.mjs` needs the trusted in-app native pipe bridge. For now, validate it by running a manual Yukino Browser task and then using strict post-install smoke to match the Browser turn logs.
- `plugin_cache_windows_file_lock` can be historical/recovered on Windows. Treat it as active damage only when paired with an incomplete `chrome\latest` cache, pending cleanup entries, or a bad native host target.
- Do not reinstall Yukino while the user is actively using it unless they explicitly approve the install smoke or release install.

## Next Roadmap

### Stability First

- Keep this release as the stable baseline until a new upstream Codex package needs migration.
- Keep `npm test`, `verify-yukino.ps1`, `scripts\Test-YukinoLocalState.ps1`, strict post-install Browser smoke after manual GUI Browser use, `git diff --check`, manual GUI smoke, and release install smoke as the minimum release closure bundle.
- Keep generated directories out of git: `out/`, `logs/`, and `src_unpacked/`.

### Product Clarity

- Add an in-app About or version surface that clearly says this is Yukino, shows the installed package version, and separates it from official Codex.
- Keep local diagnostics tucked into Settings rather than adding a visible diagnostics page. The first UI step is the Agent Settings > Workspace Dependencies row that copies `npm run diagnose`; a future one-click runner should wait until the main-process IPC path is verified.
- Make plugin and skill status easier to inspect from the UI before changing deeper runtime behavior.

### Update Discipline

- Before each upstream migration, update tests for changed minified bundle shapes first, then adjust patch code.
- Run the release safety gate before every publish.
- Run the real release install smoke after publishing private assets.
- Record the final tag, SHA256, installed package full name, verification output, and manual GUI smoke result in a baseline note like this one.

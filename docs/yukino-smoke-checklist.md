# Yukino Smoke Checklist

Use this checklist after rebuilding, installing, or publishing a Yukino build.

For the current stable release baseline, see [yukino-v26.506.3741.1-baseline.md](yukino-v26.506.3741.1-baseline.md).

## Stable Maintenance Baseline

- Start from a clean worktree: `git status --short --branch` should show only the branch line.
- Confirm the maintenance HEAD is pushed before judging local diagnostics.
- Run `npm test`.
- Run `npm run verify`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-YukinoLocalState.ps1`.
- Expected local diagnostic result: `Local state diagnostic passed`.
- Treat a dirty-worktree warning as a development state, not a product issue; rerun after committing.

## Build Artifacts

- Run `npm test`.
- Run `npm run verify`.
- Run `npm run diagnose` for a read-only local state report.
- Confirm latest build directory under `logs\build-*`.
- Confirm latest MSIX under `out\yukino.akane_*_x64.msix`.
- Confirm `C:\Users\Administrator\.yukino\build-history.jsonl` records the latest build when a build was run.
- Confirm `C:\Users\Administrator\.yukino\verify-history.jsonl` records the latest verification when verification was run.

## Browser Runtime

- Confirm `browser-use@openai-bundled` is enabled in `.yukino`.
- Confirm local diagnostics report `browser-use-runtime-log` as PASS after Browser has been triggered.
- After a manual Browser task in Yukino, run `scripts\Test-YukinoPostInstallBrowserSmoke.ps1 -MinLogTime (Get-Date).AddMinutes(-10) -RequireBrowserRuntimeActivity`.
- Expected strict result: matched `IAB_LIFECYCLE` Browser turn start/end log lines with the same `turnId`.

## Chrome Extension And Plugin Cache

- Confirm `chrome@openai-bundled` is enabled in `.yukino`.
- Confirm `installed-chrome-plugin-cache` is PASS.
- Confirm `chrome-plugin-cache-pending-cleanup` is PASS.
- Confirm `chrome-native-host-yukino-target` points at `%USERPROFILE%\.yukino\plugins\cache\openai-bundled\chrome\latest\extension-host\windows\x64\extension-host.exe`.
- Treat `plugin_cache_windows_file_lock` as PASS when it is historical/recovered, the `latest` cache is complete, there are no pending cleanup entries, and the native host target is correct.

## Desktop UI

- Confirm Plugins page opens from the sidebar.
- Confirm Skills page still opens separately.
- Confirm the Plugins page does not fall back to the default Skills tab.
- Confirm settings write behavior still works after changing an Agent Settings value.
- Confirm Agent Settings > Workspace Dependencies contains the quiet Yukino version row and that it copies the package, release, and config-home identity.
- Confirm Agent Settings > Workspace Dependencies contains the quiet Yukino local diagnostics row, click `Run diagnostics`, and confirm the result is copied with a success/warning toast.
- Confirm there is no standalone diagnostics nav item or diagnostics page in the main settings sidebar.
- Confirm the sidebar background is visible and not stretched.
- Confirm `.yukino` remains the active config home.
- Confirm official OpenAI.Codex remains installed and separate from Yukino.
- After a manual Browser task in Yukino, run `scripts\Test-YukinoPostInstallBrowserSmoke.ps1 -MinLogTime (Get-Date).AddMinutes(-10) -RequireBrowserRuntimeActivity` to verify the matched Browser turn log evidence.

## Release Safety

- Run `scripts\Test-YukinoReleaseSafety.ps1` before every publish.
- Confirm the GitHub repository is private.
- Confirm tracked files do not include credential/config paths, high-confidence key/token patterns, CPA skill identifiers, or CPA-related MSIX paths.

## Manual GUI Smoke

- Open the installed Yukino app.
- Confirm the Yukino icon and sidebar background are visible.
- Confirm Plugins and Skills navigation behave separately.
- Confirm Browser can perform one harmless web task from Yukino.
- Confirm Agent Settings can still save a deliberate setting change when validating the settings write patch.

## Release

- Confirm `SHA256SUMS.txt` matches the released MSIX.
- Confirm GitHub release assets include the MSIX, `Yukino.cer`, `SHA256SUMS.txt`, and `Install-YukinoRelease.ps1`.
- Do not reinstall while the user is actively using Yukino unless they explicitly approve it.
- After publishing, run `scripts\Test-YukinoReleaseInstall.ps1 -Tag <tag>` when the user has approved a real release install smoke.

## Release Install Smoke

- Download the private release assets through `scripts\Test-YukinoReleaseInstall.ps1 -Tag <tag>`.
- Confirm `SHA256SUMS.txt` matches the downloaded MSIX.
- Confirm the published installer path runs, `verify-yukino.ps1` passes, Yukino launches, and post-install Browser smoke runs.
- Confirm the post-install summary reports Startup, Browser runtime, Chrome extension, Plugin cache, Chrome launch, and Overall in one table.

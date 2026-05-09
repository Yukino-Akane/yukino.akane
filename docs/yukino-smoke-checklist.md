# Yukino Smoke Checklist

Use this checklist after rebuilding, installing, or publishing a Yukino build.

For the current stable release baseline, see [yukino-v26.506.3741.1-baseline.md](yukino-v26.506.3741.1-baseline.md).

## Build Artifacts

- Run `npm test`.
- Run `npm run verify`.
- Run `npm run diagnose` for a read-only local state report.
- Confirm latest build directory under `logs\build-*`.
- Confirm latest MSIX under `out\yukino.akane_*_x64.msix`.
- Confirm `C:\Users\Administrator\.yukino\build-history.jsonl` records the latest build when a build was run.
- Confirm `C:\Users\Administrator\.yukino\verify-history.jsonl` records the latest verification when verification was run.

## Desktop UI

- Confirm Plugins page opens from the sidebar.
- Confirm Skills page still opens separately.
- Confirm the Plugins page does not fall back to the default Skills tab.
- Confirm settings write behavior still works after changing an Agent Settings value.
- Confirm Agent Settings > Workspace Dependencies contains the quiet Yukino local diagnostics row and that it copies `npm run diagnose`.
- Confirm there is no standalone diagnostics nav item or diagnostics page in the main settings sidebar.
- Confirm the sidebar background is visible and not stretched.
- Confirm `.yukino` remains the active config home.
- Confirm official OpenAI.Codex remains installed and separate from Yukino.
- After a manual Browser task in Yukino, run `scripts\Test-YukinoPostInstallBrowserSmoke.ps1 -MinLogTime (Get-Date).AddMinutes(-10) -RequireBrowserRuntimeActivity` to verify the matched Browser turn log evidence.

## Release

- Confirm `SHA256SUMS.txt` matches the released MSIX.
- Confirm GitHub release assets include the MSIX, `Yukino.cer`, `SHA256SUMS.txt`, and `Install-YukinoRelease.ps1`.
- Do not reinstall while the user is actively using Yukino unless they explicitly approve it.
- After publishing, run `scripts\Test-YukinoReleaseInstall.ps1 -Tag <tag>` when the user has approved a real release install smoke.

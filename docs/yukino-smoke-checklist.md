# Yukino Smoke Checklist

Use this checklist after rebuilding, installing, or publishing a Yukino build.

## Build Artifacts

- Run `npm test`.
- Run `npm run verify`.
- Confirm latest build directory under `logs\build-*`.
- Confirm latest MSIX under `out\yukino.akane_*_x64.msix`.
- Confirm `C:\Users\Administrator\.yukino\build-history.jsonl` records the latest build when a build was run.
- Confirm `C:\Users\Administrator\.yukino\verify-history.jsonl` records the latest verification when verification was run.

## Desktop UI

- Confirm Plugins page opens from the sidebar.
- Confirm Skills page still opens separately.
- Confirm the Plugins page does not fall back to the default Skills tab.
- Confirm settings write behavior still works after changing an Agent Settings value.
- Confirm the sidebar background is visible and not stretched.
- Confirm `.yukino` remains the active config home.
- Confirm official OpenAI.Codex remains installed and separate from Yukino.

## Release

- Confirm `SHA256SUMS.txt` matches the released MSIX.
- Confirm GitHub release assets include the MSIX, `Yukino.cer`, `SHA256SUMS.txt`, and `Install-YukinoRelease.ps1`.
- Do not reinstall while the user is actively using Yukino unless they explicitly approve it.

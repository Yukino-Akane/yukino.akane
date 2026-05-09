# Yukino 26.506.3741.1 Baseline

This document records the first stable Yukino baseline after the 2026-05-09 release hardening pass.

## Baseline

- Release tag: `v26.506.3741.1-yukino.1`
- Release page: `https://github.com/Yukino-Akane/yukino.akane/releases/tag/v26.506.3741.1-yukino.1`
- Published package: `yukino.akane_26.506.3741.1_x64.msix`
- MSIX SHA256: `452B3ADD02530A01BE87AEF9223590EFC754B7C190E3D1F4BB122199000AB657`
- Installed package: `yukino.akane_26.506.3741.1_x64__fnxqm6pztzbs0`
- Current maintenance HEAD after hardening: `f11af71 chore: add release install smoke`

The release assets remain valid. The later `f11af71` commit improves maintenance scripts and verification logic; it does not require republishing the MSIX by itself.

## What Was Stabilized

- Restored Yukino branding and executable icon verification after the app icon fell back to the official default icon.
- Fixed the sidebar Plugins route so it opens `/plugins` with `initialMode=browse` and `initialTab=plugins`, instead of falling back to Skills.
- Fixed the Plugins marketplace entry by requiring the patched entry gate to stay enabled as `&&!0`; the bad `&&!1` form disables the Plugins page.
- Added a private-release safety gate that rejects a non-private repo, tracked credential/config paths, high-confidence key/token patterns, CPA skill identifiers, and CPA-related paths inside the MSIX.
- Confirmed the CPA skill was not included in the repo or release assets.
- Added a real release install smoke script: `scripts\Test-YukinoReleaseInstall.ps1`.
- Cleaned verification noise so `verify-yukino.ps1` reports real risks instead of upstream-shape or unrelated-log false warnings.

## Verification Evidence

Use these commands for this baseline:

```powershell
npm test
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-yukino.ps1
git diff --check
```

Latest expected result:

- `npm test`: PASS.
- `verify-yukino.ps1`: PASS with zero warnings.
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
- Do not reinstall Yukino while the user is actively using it unless they explicitly approve the install smoke or release install.

## Next Roadmap

### Stability First

- Keep this release as the stable baseline until a new upstream Codex package needs migration.
- Keep `npm test`, `verify-yukino.ps1`, `git diff --check`, manual GUI smoke, and release install smoke as the minimum release closure bundle.
- Keep generated directories out of git: `out/`, `logs/`, and `src_unpacked/`.

### Product Clarity

- Add an in-app About or version surface that clearly says this is Yukino, shows the installed package version, and separates it from official Codex.
- Add a compact local diagnostics view for `.yukino`, plugins, enabled bundled skills, sandbox mode, approval policy, and recent logs.
- Make plugin and skill status easier to inspect from the UI before changing deeper runtime behavior.

### Update Discipline

- Before each upstream migration, update tests for changed minified bundle shapes first, then adjust patch code.
- Run the release safety gate before every publish.
- Run the real release install smoke after publishing private assets.
- Record the final tag, SHA256, installed package full name, verification output, and manual GUI smoke result in a baseline note like this one.

# Yukino Akane

Yukino Akane is a local maintenance workspace for rebuilding the installed Codex Desktop MSIX as a branded Yukino package.

This is a transitional local verification workflow. Before publishing public releases, migrate the patches to a reproducible source-based build from the open-source `openai/codex` codebase instead of distributing an MSIX rebuilt from an installed desktop package.

The repository tracks the rebuild scripts, source branding assets, verification tests, and operator notes only. Generated package copies, extracted ASAR trees, verification directories, MSIX files, certificates, credentials, and logs are intentionally ignored because they are large, reproducible, or machine-local.

## Current State

- Source package: installed `OpenAI.Codex`, latest observed version `26.506.3741.0`.
- Target package: `yukino.akane`.
- Display name: `Yukino`.
- Publisher: `CN=Yukino`.
- Latest built package: `out/yukino.akane_26.506.3741.1_x64.msix`.
- Latest installed package observed: `yukino.akane_26.506.3741.1_x64__fnxqm6pztzbs0`.
- Stable private release baseline: `v26.506.3741.1-yukino.2`.
- Config home: `%USERPROFILE%\.yukino`.

## Files

- `build-yukino.ps1`: copies the installed Codex Desktop package, patches branding and runtime assets, repacks `app.asar`, signs an MSIX, and can install it.
- `verify-yukino.ps1`: checks the latest build output, installed package, config state, and recent app logs for the expected Yukino patches.
- `scripts/Test-YukinoLocalState.ps1`: read-only local diagnostic for installed packages, `.yukino` config, plugins, logs, repo state, and release assets.
- `assets/`: source images for Yukino AppX icons, the executable icon, and the desktop sidebar background.
- `scripts/`: helper scripts used by the rebuild workflow.
- `tests/`: focused PowerShell checks for source asset generation and injected UI patches.
- `MOD_NOTES.md`: patch inventory, build flow, verification notes, and known follow-ups.
- `docs/yukino-v26.506.3741.1-baseline.md`: stable release baseline, incident lessons, verification evidence, and next roadmap.

## Build

Run from this directory:

```powershell
npm run build
```

Equivalent direct command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-yukino.ps1
```

To install after building:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-yukino.ps1 -Install
```

If Yukino is currently running, the build script skips the temporary source smoke launch so it does not interrupt the active desktop session. You can also skip that smoke launch explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-yukino.ps1 -SkipSmoke
```

The script resolves the currently installed `OpenAI.Codex` package and emits a target version whose revision is one higher than the source package revision.

## Verify

```powershell
npm run verify
```

Equivalent direct command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-yukino.ps1
```

The latest known verification keeps the `[windows] sandbox` value as a compatibility check because the current desktop runtime may still require it. The active top-level config values were valid:

- `approval_policy = "never"`
- `sandbox_mode = "danger-full-access"`
- `[windows] sandbox = "elevated"`
- `features.plugins = true`
- `browser-use@openai-bundled` enabled

For Codex Desktop `26.506.2212.0`, the rebuild also patches the combined sidebar `Plugins` nav item so it opens the `/plugins` route with the Plugins browse tab selected instead of falling through to the default Skills tab when the desktop route flag labels that item as Plugins.

Run all focused maintenance tests with:

```powershell
npm test
```

Run a read-only local diagnostic when investigating a machine-specific issue:

```powershell
npm run diagnose
```

Equivalent direct command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-YukinoLocalState.ps1
```

The rebuilt UI also keeps maintenance identity quiet: in Agent Settings > Workspace Dependencies, Yukino shows a version row that copies the package/release/config-home identity and a local diagnostics row with `Run diagnostics`. That button runs the bundled read-only local diagnostic with `-NoRepair` through a fixed app-server method, copies the bounded report, and keeps `npm run diagnose` as the fallback command. It does not add a standalone diagnostics page.

After installation or release, use [docs/yukino-smoke-checklist.md](docs/yukino-smoke-checklist.md) for the manual GUI checks.

The current stable baseline and roadmap are recorded in [docs/yukino-v26.506.3741.1-baseline.md](docs/yukino-v26.506.3741.1-baseline.md).

## Install From A Private Release

Download the MSIX package, `Yukino.cer`, `SHA256SUMS.txt`, and `Install-YukinoRelease.ps1` from the private GitHub release, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-YukinoRelease.ps1
```

Run PowerShell as administrator if you want the signing certificate installed for all users. Without administrator privileges, the script imports the certificate into the current user's certificate stores.

## Publish A Private Release

After a build has produced `out/yukino.akane_<version>_x64.msix`, prepare release assets and run verification without touching GitHub:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Publish-YukinoRelease.ps1 -Tag v<version>-yukino.<n> -DryRun
```

When the dry-run output looks right, publish the release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Publish-YukinoRelease.ps1 -Tag v<version>-yukino.<n> -Title "Yukino Codex <version>-yukino.<n>" -Latest
```

The publish script recalculates `SHA256SUMS.txt`, copies `Install-YukinoRelease.ps1` into `out/`, writes release notes, runs `verify-yukino.ps1`, and uploads the MSIX, certificate, checksum file, and installer through `gh release create`.

Publishing also runs `scripts\Test-YukinoReleaseSafety.ps1`. The safety gate requires the GitHub repository to be private and rejects tracked credential/config paths, high-confidence key/token patterns, CPA skill names, and CPA-related paths inside the MSIX.

After publishing, run the real release install smoke when the user has approved reinstalling Yukino:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-YukinoReleaseInstall.ps1 -Tag v<version>-yukino.<n>
```

The install smoke downloads the private GitHub release assets, verifies `SHA256SUMS.txt`, runs the published installer, runs `verify-yukino.ps1`, launches the installed `Yukino.exe`, and removes the temporary download directory.

When you have just performed a manual Browser GUI smoke in Yukino, rerun the post-install Browser smoke in strict mode to pin the real Browser tool turn to the current log window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-YukinoPostInstallBrowserSmoke.ps1 -MinLogTime (Get-Date).AddMinutes(-10) -RequireBrowserRuntimeActivity
```

## Repository Policy

Do not commit generated directories:

- `src_unpacked/`
- `out/`
- `logs/`

These directories can contain many gigabytes of copied package contents and repeated extracted builds. If a generated artifact needs to be preserved, record its path and verification result in `MOD_NOTES.md` instead of committing the artifact.

Do not commit local credentials or runtime identity files, including `.env`, `.yukino/`, `.codex/`, `auth.json`, `credentials.json`, or `*.credentials.json`.

# Yukino Akane

Yukino Akane is a local maintenance workspace for rebuilding the installed Codex Desktop MSIX as a branded Yukino package.

This is a transitional local verification workflow. Before publishing public releases, migrate the patches to a reproducible source-based build from the open-source `openai/codex` codebase instead of distributing an MSIX rebuilt from an installed desktop package.

The repository tracks the rebuild scripts, source branding assets, verification tests, and operator notes only. Generated package copies, extracted ASAR trees, verification directories, MSIX files, certificates, credentials, and logs are intentionally ignored because they are large, reproducible, or machine-local.

## Current State

- Source package: installed `OpenAI.Codex`, latest observed version `26.429.2026.0`.
- Target package: `yukino.akane`.
- Display name: `Yukino`.
- Publisher: `CN=Yukino`.
- Latest built package: `out/yukino.akane_26.429.2026.1_x64.msix`.
- Latest installed package observed: `yukino.akane_26.429.2026.1_x64__fnxqm6pztzbs0`.
- Config home: `%USERPROFILE%\.yukino`.

## Files

- `build-yukino.ps1`: copies the installed Codex Desktop package, patches branding and runtime assets, repacks `app.asar`, signs an MSIX, and can install it.
- `verify-yukino.ps1`: checks the latest build output, installed package, config state, and recent app logs for the expected Yukino patches.
- `assets/`: source images for Yukino app icons and the desktop sidebar background.
- `scripts/`: helper scripts used by the rebuild workflow.
- `tests/`: focused PowerShell checks for source asset generation and injected UI patches.
- `MOD_NOTES.md`: patch inventory, build flow, verification notes, and known follow-ups.

## Build

Run from this directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-yukino.ps1
```

To install after building:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-yukino.ps1 -Install
```

The script resolves the currently installed `OpenAI.Codex` package and emits a target version whose revision is one higher than the source package revision.

## Verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-yukino.ps1
```

The latest known verification keeps the `[windows] sandbox` value as a compatibility check because the current desktop runtime may still require it. The active top-level config values were valid:

- `approval_policy = "never"`
- `sandbox_mode = "danger-full-access"`
- `[windows] sandbox = "elevated"`
- `features.plugins = true`
- `browser-use@openai-bundled` enabled

## Repository Policy

Do not commit generated directories:

- `src_unpacked/`
- `out/`
- `logs/`

These directories can contain many gigabytes of copied package contents and repeated extracted builds. If a generated artifact needs to be preserved, record its path and verification result in `MOD_NOTES.md` instead of committing the artifact.

Do not commit local credentials or runtime identity files, including `.env`, `.yukino/`, `.codex/`, `auth.json`, `credentials.json`, or `*.credentials.json`.

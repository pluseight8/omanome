# Release and recovery runbook

Omanome releases are source releases for the existing Omarchy plugin contract.
The standard bar, the installed Omarchy shell, and user configuration remain
outside the release archive.

## Before a release

1. Update `manifest.json`, `hypr/omanome-hypr/compatibility.json`, README files,
   and `CHANGELOG.md` to the same semver.
2. Run `make check`, `make companion-check`, `make dependency-audit`,
   `make performance-test`, `make performance-check`, `make input-check`,
   `make hardware-test`, and `make version-check`.
3. Run `omarchy plugin validate .` and `./cli/omanome doctor` on an Omarchy
   host. Portable CI cannot certify a physical touchscreen, stylus, sensor, or
   loaded companion.
4. Publish the commit to `main` and wait for the push Actions run to be green.
5. For the 0.9.0 cut, the `Omanome Release` workflow observes the successful
   `Omanome CI` run on `main`, reads the version from `manifest.json`, creates
   or updates the annotated `v0.9.0` tag on that exact green commit, then
   validates the tag, runs the portable and companion checks, creates a source
   archive plus SHA-256 checksum, and publishes the GitHub release. The
   workflow is version-agnostic for later semver cuts.

## Recovery operations

`omanome update --check --json` is read-only. `omanome update --dry-run --json`
is also read-only apart from normal command diagnostics. A real update creates a
snapshot and journal before calling Omarchy. If the update command or health
check fails, the prior checkout is restored and the failed state is retained.

The default `stable` channel resolves the latest non-prerelease GitHub Release
tag and never follows arbitrary commits on `main`. `beta` follows the `beta`
branch, while `main` is the explicit development channel; `nightly` remains a
legacy branch channel for existing configurations. No channel installs updates
automatically: the user must run `omanome update` explicitly.

If a session stops during an update, run:

```sh
omanome recover --json
omanome doctor --json
```

Use `omanome rollback --list --json` to inspect snapshots and
`omanome rollback <snapshot-id>` only after reviewing the metadata. The optional
Hyprland companion has a separate pending-load marker and remains disabled
after an unconfirmed load; `omanome companion recover` restores its newest
user-owned backup without enabling it.

Support bundles contain capability, version, validation, and lifecycle metadata.
They do not include config values, clipboard payloads, window titles, typed text,
or secrets. Review the archive before sharing it.

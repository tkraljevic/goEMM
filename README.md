# goEMM — downloads

Release binaries for [goEMM](https://github.com/tkraljevic/goEMM): a local,
user-owned shared memory for AI assistants.

**This repository holds builds, not source.** Nothing here is compiled from
anything in this repository — the source lives elsewhere and is not published.
What you will find under Releases:

- `emm-<os>-<arch>` — the binary, one per platform
- `emm-tray-<os>-<arch>` — the tray launcher
- `SHA256SUMS.txt` — checksums for every asset in that release

## Install

    curl -fsSL <install.sh URL> | sh

The installer verifies every download against `SHA256SUMS.txt` before putting
anything in place, and refuses to install a binary that will not run.

## Updating

goEMM updates itself and keeps a copy of the version it replaces:

    emm update
    emm update rollback

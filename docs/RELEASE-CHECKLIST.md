# v0.2.0-winboat release checklist

This is the first practical Ubuntu-use release through WinBoat. It is **not** a production native Linux driver release.

## Metadata

- Tag: `v0.2.0-winboat`
- Title: `IRIScan Express 4 v0.2.0 — WinBoat support`
- Working method: Ubuntu + WinBoat + official Windows driver
- Native method: experimental; C3 `resid=78` remains unresolved

## Build and verify

```bash
bash scripts/check.sh
bash scripts/build-release.sh
sha256sum -c dist/IRIScan-Express4-v0.2.0-SHA256SUMS.txt
```

Expected assets:

1. `iriscan-express4-winboat-tools-0.2.0.tar.gz`
2. `iriscan-express4-winboat-tools-0.2.0.zip`
3. `iriscan-express4-winboat-support_0.2.0_all.deb`
4. `IRIScan-Express4-v0.2.0-SHA256SUMS.txt`

The Debian package must contain no maintainer script that edits compose or restarts WinBoat.

## Release gates

- CI, fixture tests, package inspection, and checksum verification pass.
- Dry-run against a sanitized real compose copy changes only `ARGUMENTS`.
- Privacy scan finds no private paths, credentials, serials, unrelated infrastructure markers, proprietary binaries, captures, or scanned content.
- README and notes clearly separate working-now WinBoat from experimental native Linux.

End-to-end acceptance requires the user to verify the physical PnP device, save two scans, and confirm persistence after restart.

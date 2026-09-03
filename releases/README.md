# Public test artifacts

Version `v0.1.0-research` is intentionally a **research/pre-release**, not a production scanner driver.

Recommended public assets:

- `iriscan-express4-diagnostic_0.1.0_all.deb` — safe diagnostic package; does not install a scanner driver or send scan/motor commands.
- `iriscan-express4-diagnostic-tools-0.1.0.tar.gz` — portable diagnostic scripts.
- `iriscan-express4-linux-0.1.0-research.tar.gz` — full source/research tree.
- `iriscan-express4-linux-0.1.0-research.zip` — same source/research tree as ZIP.
- `0.1.0-research-SHA256SUMS.txt` — published checksums for all four assets.

See `../docs/RELEASE-CHECKLIST.md` before publishing or replacing any release asset.

Do not label this release as a working Linux driver until complete native image acquisition is confirmed and repeated successfully.

# v0.1.0-research release checklist

This project is **not yet a production Linux scanner driver**. The v0.1.0 line is a research/pre-release intended for hardware comparison, safe diagnostics, protocol review and experimental development.

## Release metadata

- Tag: `v0.1.0-research`
- Title: `IRIScan Express 4 Linux v0.1.0-research`
- Mark as: **Pre-release**
- Do not mark as Latest/Stable driver support.

## Assets

Attach these files to the GitHub Release:

1. `iriscan-express4-linux-0.1.0-research.zip`
2. `iriscan-express4-linux-0.1.0-research.tar.gz`
3. `iriscan-express4-diagnostic_0.1.0_all.deb`
4. `iriscan-express4-diagnostic-tools-0.1.0.tar.gz`
5. `0.1.0-research-SHA256SUMS.txt`

Verify every asset against `releases/0.1.0-research-SHA256SUMS.txt` before publishing.

## Required release warning

> Experimental research release. Safe diagnostics are available, and native Linux control has reached initialization, scan setup, physical paper transport, status polling and image-buffer discovery. Complete native image transfer is not yet proven; the current research blocker is vendor opcode C3 and repeatable SG_IO `io.resid=78` behavior. Do not treat this release as a production SANE driver.

## Validation before publishing

```bash
git clone https://github.com/aagprojectsteam-max/iriscan-express4-linux.git
cd iriscan-express4-linux
bash scripts/check.sh
```

Expected final line:

```text
CHECKS=PASS
```

Safe hardware testers may then run:

```bash
bash tools/iriscan-diagnose.sh
sudo bash tools/iriscan-safe-inquiry.sh
```

The experimental scan path physically moves paper and must be run only after reading `docs/TESTING.md` and `SECURITY.md`:

```bash
bash scripts/prepare-and-run-experimental-scan.sh
```

## Privacy/legal gate

Before every release verify that no artifact contains:

- reference scanner serial number
- local usernames/home paths
- passwords/tokens
- WinBoat/Otzar/other unrelated machine configuration
- proprietary IRIS/Avision Windows DLL/EXE/driver binaries
- private scanned documents
- unsanitized USB captures

## Promotion criteria

Do not promote beyond research/experimental status until native Linux produces a complete valid page and succeeds for at least two consecutive scans. SANE/DEB production claims require additional reboot/replug/permissions/regression testing.

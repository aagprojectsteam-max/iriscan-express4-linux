# Testing guide

## Level 1 — read-only diagnostics

Run `./tools/iriscan-diagnose.sh`. This is the preferred first contribution from new hardware owners.

## Level 2 — standard SCSI INQUIRY

Run `sudo ./tools/iriscan-safe-inquiry.sh`. This sends only standard SCSI INQUIRY (`0x12`) after verifying the USB and SCSI identities.

## Level 3 — experimental scan replay

Run `./scripts/run-experimental-scan.sh` only on an IRIScan Express 4 and only with its block node unmounted. The script sends reverse-engineered vendor commands and moves paper. The present implementation is expected to reach the known image-transfer blocker rather than produce a complete page.

When reporting results, include distro/kernel, SCSI revision, the log, and whether the paper transport behaved normally.

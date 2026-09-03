# Working-now path: WinBoat

This is the practical Ubuntu route while native image transfer remains experimental.

## What the toolkit changes

WinBoat passes extra QEMU options through the compose environment variable `ARGUMENTS`. The installer appends exactly one device selector:

```text
-device usb-host,vendorid=0x0a38,productid=0x0161
```

It never rewrites the compose file as a new template. It preserves the existing scalar and every unrelated QEMU argument, requires the existing `/dev/bus/usb:/dev/bus/usb` exposure, previews a unified diff, validates before replacement, and creates a sibling backup named like `docker-compose.yml.iriscan-backup-YYYYMMDD-HHMMSS`.

No command restarts containers, modifies disks, or installs Windows software.

## Workflow

Stop WinBoat normally if it is running, then run:

```bash
bash scripts/winboat/iriscan-winboat-preflight.sh
bash scripts/winboat/iriscan-winboat-install.sh --dry-run
bash scripts/winboat/iriscan-winboat-install.sh
```

Review the diff. Restart WinBoat normally and then run `bash scripts/winboat/iriscan-winboat-verify.sh`.

If auto-discovery finds zero or multiple compose files, pass `--compose /path/to/docker-compose.yml` explicitly.

## Status and diagnostics

```bash
bash scripts/winboat/iriscan-winboat-status.sh
bash scripts/winboat/iriscan-winboat-support-bundle.sh
```

Host verification proves the scanner is connected, the compose file exposes the USB bus, the QEMU argument exists, and—when running—the container sees `/dev/bus/usb`. Only Windows PnP verification and a real saved page prove end-to-end success.

## Removal and rollback

```bash
bash scripts/winboat/iriscan-winboat-remove.sh --dry-run
bash scripts/winboat/iriscan-winboat-remove.sh
```

Removal edits only the matching IRIS selector and creates another backup. This is safer than restoring an old whole-file backup after unrelated WinBoat settings have changed. Timestamped files remain next to the compose file for manual disaster recovery; compare them before restoration.

The editor supports `ARGUMENTS: "..."` and `- ARGUMENTS=...`. It refuses ambiguous or missing entries. Package installation only copies commands under `/usr/bin` and support code under `/usr/lib`.

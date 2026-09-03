# IRIScan Express 4 on Ubuntu

Practical Ubuntu support for the **IRIScan Express 4** (`USB 0a38:0161`), with two deliberately separate paths.

| Path | Status | Best for |
|---|---|---|
| Ubuntu → WinBoat → Windows → official IRIS/Avision driver | **WORKING METHOD** | People who need to scan now |
| Native Linux over `SG_IO` | **EXPERIMENTAL** | Developers and hardware testers |

There is no production SANE backend yet. Paper movement is not the same as a completed scan, and this project does not claim native scanning works until full image acquisition passes the published success gate.

## Option 1 — use the scanner now on Ubuntu

The practical route passes the physical USB scanner to Windows in [WinBoat](https://github.com/TibixDev/winboat), where the official IRIS/Avision Windows stack performs the scan.

```bash
git clone https://github.com/aagprojectsteam-max/iriscan-express4-linux.git
cd iriscan-express4-linux

bash scripts/winboat/iriscan-winboat-preflight.sh
bash scripts/winboat/iriscan-winboat-install.sh --dry-run
bash scripts/winboat/iriscan-winboat-install.sh
bash scripts/winboat/iriscan-winboat-verify.sh
```

The installer changes only WinBoat's QEMU `ARGUMENTS` value, adding:

```text
-device usb-host,vendorid=0x0a38,productid=0x0161
```

It preserves existing arguments, refuses missing USB-bus exposure, avoids duplicates, validates the compose file, and creates a timestamped backup. It does not restart WinBoat or touch other USB devices, storage, containers, or Windows data.

After applying the change, restart WinBoat through its normal UI and complete the lawful official-driver setup in Windows. See [WinBoat setup](docs/WINBOAT.md) and [Windows driver verification](docs/WINDOWS-SETUP.md).

Rollback removes only the managed IRIS argument:

```bash
bash scripts/winboat/iriscan-winboat-remove.sh --dry-run
bash scripts/winboat/iriscan-winboat-remove.sh
```

Installing the optional `.deb` only installs these commands; it does **not** edit or restart WinBoat.

## Option 2 — native Linux (experimental)

The native research path dynamically finds the scanner's `/dev/sgX`, verifies both USB and SCSI identity, replays the captured 300 DPI Color setup, starts paper transport, polls status, and reaches a real image-buffer descriptor.

Confirmed on the reference unit:

- USB detection and standard SCSI INQUIRY
- scanner initialization and captured 300 DPI Color setup
- paper transport and status polling
- ready descriptor (`width=2592`, `plane_rows=240`, non-zero address)

Current blocker: vendor opcode `0xC3` returns successful SCSI/host/driver status but a repeatable Linux `io.resid=78` for both 65536-byte and 32768-byte requests. The code now records sentinel-buffer modification boundaries, hashes, residuals, sense data, and all SG status fields. It does not ignore the residual or manufacture missing bytes.

Safe validation and diagnostics:

```bash
bash scripts/check.sh
bash tools/iriscan-diagnose.sh
sudo bash tools/iriscan-safe-inquiry.sh
```

The experimental scan command sends vendor commands and physically moves paper. Read [Testing](docs/TESTING.md) and [Security](SECURITY.md) first:

```bash
bash scripts/prepare-and-run-experimental-scan.sh
```

See [protocol notes](docs/PROTOCOL.md), [C3 forensics](docs/C3-FORENSIC.md), and [development status](docs/DEVELOPMENT-STATUS.md).

## Option 3 — help test

Create a narrowly scoped, redacted archive and attach it to a Hardware Report issue:

```bash
bash scripts/winboat/iriscan-winboat-support-bundle.sh
```

Review the archive before publishing it. It excludes unrelated disk inventories and redacts scanner serials, usernames, home paths, common credentials, and token shapes by default.

## Repository layout

```text
scripts/winboat/  safe WinBoat detection, install, verify, removal and support tools
tests/            fixture tests for idempotency, preservation and rollback
packaging/        non-destructive Debian package metadata
src/              experimental native Linux implementation
tools/            safe diagnostics, compose editor and image conversion
protocol/         sanitized captured-operation transcripts
docs/             user, protocol, privacy and development documentation
releases/         release notes and checksums
```

The public protocol uses a serial placeholder. The connected scanner's serial is inserted only into a private runtime copy. `/dev/sgX` is never hard-coded.

## Legal and privacy

This independent interoperability project is not affiliated with IRIS or Avision. It does not redistribute proprietary vendor drivers, DLLs, executables, private captures, or scanned documents. Obtain the Windows software from an official/licensed source.

MIT licensed. See [LICENSE](LICENSE).

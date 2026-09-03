# IRIScan Express 4 Linux Support

Experimental, open-source Linux support and reverse-engineering toolkit for the **IRIScan Express 4** (`USB 0a38:0161`).

> **Research status:** this project can identify the scanner, communicate through Linux `SG_IO`, replay initialization, configure the captured 300 DPI color mode, start the motor/paper transport, poll scan status, and discover an image buffer. Complete native image transfer is **not yet production-ready**; the current blocker is the vendor-specific `C3` image-read path and its repeatable Linux `io.resid=78` behavior.

## Current status

| Capability | Status |
|---|---|
| USB detection (`0a38:0161`) | PASS |
| SCSI / `SG_IO` communication | PASS |
| Standard INQUIRY | PASS |
| Captured initialization replay | PASS |
| 300 DPI color setup | PASS |
| Motor / paper transport | PASS |
| Status polling | PASS |
| Image-buffer discovery | PASS |
| C3 image transfer | EXPERIMENTAL |
| Complete native scan | NOT YET |
| SANE backend | PLANNED |
| NAPS2 / desktop scanner integration | PLANNED |

## Hardware model

The Express 4 presents a single USB Mass Storage / SCSI Transparent interface rather than USB Scanner Class:

```text
IRIScan Express 4
  USB 0a38:0161
       |
       +-- Mass Storage class (08)
           SCSI Transparent subclass (06)
           Bulk-Only protocol (50)
           Bulk IN  0x81
           Bulk OUT 0x02
```

Linux normally attaches `usb-storage`. The scanner identifies over SCSI as vendor `IRIS`, model `IRIScanExpress4`, revision `0.11` on the reference device.

## Start here

### Safe diagnostics

The diagnostic tools do not start a scan:

```bash
sudo apt install sg3-utils usbutils
./tools/iriscan-diagnose.sh
```

For a minimal hardware communication test using standard SCSI INQUIRY only:

```bash
sudo ./tools/iriscan-safe-inquiry.sh
```

Please attach the generated support report to a hardware-report issue if your device behaves differently.

### Experimental scanner code

Build:

```bash
./scripts/build.sh
```

The experimental scan path physically moves paper and sends reverse-engineered vendor commands. Read `docs/TESTING.md` and `SECURITY.md` before running it.

```bash
sudo ./scripts/run-experimental-scan.sh
```

This is for development/testing, not normal scanning yet.

## What has been reverse engineered

A known-good Windows scan was captured at **300 DPI Color**. The research artifacts establish a vendor command/state-machine path over SCSI/USB Mass Storage. The Linux implementation has reproduced initialization, scan start, paper movement, polling, and a real ready-buffer descriptor (`width=2592`, `plane_rows=240`, non-zero device memory address).

The unresolved boundary is image payload retrieval through vendor opcode `0xC3`. Requests of both 65536 and 32768 bytes returned successful `SG_IO` status but a repeatable residual count of 78 bytes. The project deliberately does not guess whether that residual represents missing payload or transport semantics; `docs/C3-FORENSIC.md` tracks the investigation.

## Repository layout

```text
src/        experimental Linux implementation
tools/      safe diagnostics and forensic helpers
protocol/   sanitized operation transcripts from the captured protocol
docs/       hardware, protocol, testing, privacy and development notes
scripts/    build/check/experimental-run helpers
packaging/  future udev / Debian packaging work
.github/    CI and issue templates
```

## Goals

The intended end state is:

```text
sudo apt install ./iriscan-express4_<version>_amd64.deb
scanimage -L
```

followed by normal use through SANE-compatible applications, without hard-coding `/dev/sgX`, broad `disk` permissions, or manual setup after every reboot/replug.

## Contributing / hardware testers

Additional Express 4 units are especially useful. We want to compare:

- USB descriptors and firmware revisions
- SCSI identity
- kernel/distro behavior
- C3 residual behavior
- eventual successful scan results

Please use the issue templates. Do **not** upload proprietary IRIS/Avision binaries, private documents, or unsanitized captures.

## Legal / provenance

This is an independent interoperability/research project and is not affiliated with IRIS or Avision. Vendor Windows DLL/EXE/driver binaries are intentionally not distributed here.

## License

MIT. See `LICENSE`.

# IRIScan Express 4 protocol notes

This document records **observed interoperability facts** from a known-good Windows USB capture and subsequent Linux `SG_IO` experiments. It intentionally distinguishes capture-derived facts from Linux behavior that is still under investigation.

## Device / transport

Reference device:

```text
USB VID:PID   0a38:0161
Manufacturer  IRIS
Product       IRIScanExpress4
SCSI vendor   IRIS
SCSI model    IRIScanExpress4
SCSI revision 0.11
PDT           0 (direct-access / disk)
```

The USB interface is Mass Storage / SCSI Transparent / Bulk-Only (`08/06/50`), with Bulk IN `0x81` and Bulk OUT `0x02`. Windows uses its normal storage stack; scanner control lives in userspace. Linux exposes the same device through `usb-storage` and `scsi_generic` (`/dev/sgX`).

## Vendor command layers

The working Windows capture shows two important outer SCSI opcodes:

- `0xC5`: bridge/control command transport.
- `0xC3`: scanner-memory/image-buffer read.

A repeated `0xC5` query returns ASCII `NOVA`, which is used as a bridge signature in the experimental code.

Within the `0xC5` flow, observed high-level scanner commands include:

| Inner opcode | Observed role |
|---:|---|
| `0x12` | INQUIRY |
| `0x24` | SET WINDOW |
| `0x16` | RESERVE |
| `0x1B` | START / SCAN |
| `0x28` | READ / status request |
| `0x2A` | SEND parameter/control data |
| `0x17` | RELEASE / cleanup |

These are observations from the successful capture, not a claim that every field is fully decoded.

## Proven 300 DPI color setup

The captured SET WINDOW contains X/Y resolution `0x012c` (300) and the runtime descriptor reports width `2592`. The experimental Linux implementation therefore supports **only the captured 300 DPI Color profile** for now. Other resolutions/modes must not be synthesized until separately captured or safely characterized.

## Status / image-buffer descriptor

A 24-byte descriptor read through the control path is interpreted as six little-endian 32-bit words. The fields used by the current implementation are:

```text
word 0   status code
word 3   width / pixels per plane row
word 4   plane-row count
word 5   scanner-memory address
```

A real Linux run reached:

```text
status      = 1
width       = 2592
plane_rows  = 240
address     = non-zero scanner memory address
```

`plane_rows=240` represents 240 color-plane rows, i.e. 80 RGB image rows. Therefore the buffer size is:

```text
2592 * 240 = 622080 bytes
```

Do **not** multiply this by three again.

Observed completion uses status code `3` with zero width/rows/address.

## `0xC3` image reads

Observed outer layout:

```text
byte 0      0xC3
byte 1      0x07
bytes 2-5   big-endian scanner memory address
bytes 6-9   big-endian requested length
bytes 10-15 zero in observed reads
```

The Windows capture contains 64 KiB-class C3 reads. The capture was sufficient to reconstruct the scanned page and establish a per-line planar RGB layout:

```text
R plane: width bytes
G plane: width bytes
B plane: width bytes
(repeated for each image row)
```

That capture-derived reconstruction proves that C3 carries image payload. It does **not** prove that Linux transfer accounting is already solved.

## Current Linux C3 blocker

On the reference Ubuntu system, the experimental `SG_IO` path reaches a ready image buffer, but C3 reads return successful transport/SCSI status while `sg_io_hdr_t.io.resid` is consistently `78` bytes:

```text
requested 65536 -> resid-derived length 65458
requested 32768 -> resid-derived length 32690
```

The same residual at two request sizes proves this is not merely a 64 KiB boundary issue. Earlier C5 traffic also demonstrated that `resid` is not always a trustworthy application-level byte-count contract for this private bridge protocol.

Therefore the project does **not** currently discard 78 bytes, pad them, over-request blindly, or claim complete native image acquisition. The next controlled experiment is documented in `C3-FORENSIC.md`: prefill the destination buffer with a deterministic sentinel, perform one C3 read, then compare memory changes against the kernel-reported residual boundary.

## Public protocol transcripts

`protocol/` contains sanitized operation transcripts derived from the successful Windows capture:

```text
init-parts/                   initialization (materialized by script)
scan-setup-300dpi-color.ops   captured 300 DPI RGB setup and START
next-batch.ops                post-buffer acknowledgement / next-buffer path
scan-finish.ops               captured normal RELEASE / cleanup
```

The initialization capture contained the reference unit's serial in one SEND payload. The public files replace that 16-byte field with an `aa...aa` placeholder. `run-experimental-scan.sh` materializes a private runtime copy and injects the serial read from the physically connected scanner. The personal serial is never required in the repository.

`bash scripts/materialize-protocol.sh` validates the part ordering, transaction monotonicity, operation count (`742`), and placeholder count before producing `init.ops`.

## Safety / implementation rules

Production code must not:

- hard-code `/dev/sg1`, `/dev/sg2`, USB bus, or USB device numbers;
- treat arbitrary PDT=0 disks as scanners;
- grant broad access to every `sg` or disk device;
- permanently detach or blacklist `usb-storage` globally;
- continue when the scanner's block node is mounted;
- omit the captured RELEASE/cleanup path after START;
- claim a complete scan merely because paper moved.

The final implementation should dynamically match `0a38:0161` plus IRIS/SCSI model identity, obtain narrow permissions, complete image acquisition reliably, then expose the scanner through a dedicated SANE backend.

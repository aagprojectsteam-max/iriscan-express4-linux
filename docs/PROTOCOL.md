# AAG — IRIScan Express 4: protocol decode from Windows USB capture

**Device:** IRIScan Express 4  
**USB:** `0a38:0161`  
**Serial:** `<device-serial>`  
**Firmware / SCSI revision:** `0.11`  
**Capture files:** `IRIScan-INIT.pcap`, `IRIScan-SCAN.pcap`  
**Analysis date:** 2026-08-21

## Executive result

The Windows capture is valid and sufficient to move the project from speculation to an implementable Linux userspace driver.

The capture proves that the scanner uses the standard USB Mass Storage Bulk-Only transport, but the application sends a private command protocol through SCSI CDBs. The private bridge protocol uses outer opcodes `0xC5` and `0xC3`. Inside `0xC5`, the Windows driver carries standard SCSI Scanner Command Set commands such as INQUIRY, SET WINDOW, RESERVE, SCAN, READ, SEND and RELEASE.

The image stream was successfully extracted from the capture and reconstructed into a valid page. This proves that the command framing, buffer descriptors, memory reads and image layout have all been decoded far enough to implement a native Linux scan prototype.

## Proven transport architecture

```text
IRIS TWAIN / Avision userspace driver on Windows
                  |
                  | DeviceIoControl / ReadFile / WriteFile
                  v
         Microsoft USBSTOR / SCSI layer
                  |
                  v
 USB Mass Storage Bulk-Only Transport, class 08/06/50
                  |
                  v
      IRIScan Express 4 vendor SCSI protocol
```

Linux already exposes the same device through `/dev/sgX`; therefore the Windows CDBs can be sent with Linux `SG_IO`. No new kernel driver is required for the first implementation.

## Capture inventory

| Capture | Size | BOT transactions |
|---|---:|---:|
| `IRIScan-INIT.pcap` | 531,454 bytes | 972 |
| `IRIScan-SCAN.pcap` | 34,283,608 bytes | 19,182 |

The scanner was USB bus 3, device 5 in these captures. A production implementation must not rely on those temporary numbers.

## Outer vendor CDB `0xC5`

`0xC5` is the control and scanner-command transport. The outer CDB is 16 bytes.

Typical examples:

```text
c5 07 00 00 00 00 00 00 00 04 ff 02 00 00 00 00
```

Returns ASCII:

```text
NOVA
```

This is a strong bridge identity signature.

```text
c5 07 00 00 00 00 00 00 00 0a 02 03 00 00 00 00
```

Transfers a 10-byte high-level scanner CDB to the device.

The transfer length is encoded big-endian in outer CDB bytes 8–9. Selector bytes start at byte 10.

### Useful C5 selector families observed

| Selector | Direction / size | Observed role |
|---|---:|---|
| `ff 02` | IN 4 | bridge signature, returns `NOVA` |
| `ff 03` | IN 16 | command/channel status |
| `ff 04` | IN 16 | command/channel status |
| `ff 05` | IN 16 | command/channel status |
| `ff 06` | IN 16 | command/channel status / synchronization |
| `02 03` | OUT variable | carries high-level scanner CDB and optional parameter data |
| `02 01 02` | IN 24 | side/channel 1 buffer descriptor |
| `02 02 02` | IN 24 | side/channel 2 buffer descriptor |
| `02 01 01` | IN 4 | post-buffer channel status/acknowledgement |
| `02 02 01` | IN 4 | post-buffer channel status/acknowledgement |

The exact successful command cadence has been preserved as transcript files in the Linux PoC package.

## High-level scanner commands carried inside C5

The following inner CDBs were observed and are not guesses:

| Opcode | Meaning in scanner command set | Example |
|---:|---|---|
| `0x12` | INQUIRY | `12 00 00 00 a5 00 ...` |
| `0x24` | SET WINDOW | 10-byte CDB followed by 79-byte parameter list |
| `0x16` | RESERVE | `16 00 00 00 00 00 ...` |
| `0x1B` | SCAN / start | `1b 00 00 00 00 80 ...` |
| `0x28` | READ / status or scanner data request | several data-type variants |
| `0x2A` | SEND | pages/types `0x83`, `0x85`, `0x95`, `0x96` observed |
| `0x17` | RELEASE | normal end-of-scan cleanup |
| `0x08` | scanner read/query command | observed during open and post-scan flow |

## Captured SET WINDOW

The successful scan used this exact 89-byte payload:

```text
24000000000000004f00
00000000000000470000012c012c00000000000000000000288000009600808080050800000300000000000000000000ff1de0ff001e6025801000006400640064800000000b000000000000000000
```

The first 10 bytes are the SET WINDOW CDB; the remaining 79 bytes are the window parameter list.

Decoded fields supported by the capture:

- X resolution: `0x012c` = 300 dpi.
- Y resolution: `0x012c` = 300 dpi.
- Image composition: `0x05`, multilevel RGB.
- Bits per component: `0x08`.
- Output width observed at runtime: 2592 pixels.

The capture therefore represents a **300 dpi color scan**, not 200 dpi grayscale.

## Outer vendor CDB `0xC3`

`0xC3` reads scanner memory/buffer data directly.

Layout:

```text
byte 0      0xC3
byte 1      0x07
bytes 2–5   big-endian buffer address
bytes 6–9   big-endian transfer length
bytes 10–15 zero in observed reads
```

Example:

```text
c3 07 00 a0 90 40 00 01 00 00 00 00 00 00 00 00
```

means:

```text
address = 0x00A09040
length  = 0x00010000 = 65,536 bytes
```

The Windows driver reads in 65,536-byte chunks, with a smaller final chunk per available buffer.

## Runtime 24-byte buffer descriptor

The channel-2 descriptor returned by selector `02 02 02` is six little-endian 32-bit words:

```text
word 0: status code
word 1: observed as 1
word 2: observed as 0
word 3: pixels per plane row
word 4: available plane rows
word 5: scanner memory address
```

Normal full batch example:

```text
01 00 00 00  01 00 00 00  00 00 00 00
20 0a 00 00  f0 00 00 00  40 22 46 00
```

Decoded:

```text
status       = 1, data available
width        = 0x0a20 = 2592 pixels
plane rows   = 0x00f0 = 240
address      = 0x00462240
```

Because the scan is RGB, 240 plane rows represent 80 image rows:

```text
2592 × 240 = 622,080 bytes
622,080 / (2592 × 3) = 80 RGB rows
```

Final partial batch:

```text
plane rows = 0x51 = 81 = 27 RGB rows
```

End-of-page / completion descriptor:

```text
status = 3
width = 0
plane rows = 0
address = 0
```

## Image format

The complete unique image stream is:

```text
width      = 2592 pixels
height     = 3547 pixels
channels   = 3
raw bytes  = 27,581,472
```

The raw layout is **per-line planar RGB**:

```text
for each image row:
    2592 bytes red plane
    2592 bytes green plane
    2592 bytes blue plane
```

Interleaving those three planes per pixel produces a correct image.

## PCAP truncation caveat

The USBPcap file used a snap length of 65,535 bytes. A USBPcap record also contains its own per-packet header, so nominal 65,536-byte USB data transfers were truncated by 28 bytes in the PCAP. After removing one retry overlap, 11,172 bytes were absent from the capture and were interpolated only for reconstruction preview purposes.

This is a capture artifact, not a scanner-protocol limitation. Direct Linux `SG_IO` reads request and receive the full 65,536 bytes and will not have these gaps.

## Retry overlap in Windows capture

A four-chunk overlap occurred around the transition near address `0x01596840`. The same chunks appeared twice after ordinary Windows disk-probe commands were interleaved with scanner reads. The duplicate chunks were byte-identical and were removed during reconstruction.

A native Linux implementation should:

1. identify the scanner dynamically;
2. prevent automounters from treating it as a useful disk;
3. perform full SG_IO reads;
4. validate each buffer descriptor and transfer length;
5. always send the normal RELEASE sequence on completion or error.

## Proof of reconstruction

The page in `IRIScan-SCAN.pcap` was reconstructed successfully as a 2592×3547 color image. This is the decisive proof that the protocol decode is sufficient for a first native Linux scan implementation.

Reconstruction metadata:

```json
{
  "width": 2592,
  "height": 3547,
  "channels": 3,
  "layout": "line-planar (R plane, G plane, B plane per scan line)",
  "raw_bytes": 27581472,
  "c3_commands_total": 448,
  "dropped_duplicate_chunks": [290, 291, 292, 293],
  "kept_chunks": 444,
  "capture_missing_bytes_interpolated": 11172,
  "sha256_raw_interpolated": "7081f605e998007011ca7df33cbda320bee57aeb50dcf7b7812f5185d52af01f"
}
```

## Linux implementation route

The first package produced from this decode is the initial Linux protocol PoC.

It:

- finds the exact scanner dynamically through sysfs;
- verifies USB VID/PID and serial;
- verifies SCSI vendor/model;
- opens the correct `/dev/sgX`;
- replays the captured normal initialization and 300 dpi RGB setup;
- polls the decoded 24-byte buffer descriptor;
- reads each image buffer with `0xC3` over SG_IO;
- writes line-planar RAW, PPM, PNG and metadata;
- sends the captured normal RELEASE sequence on success, failure or interruption.

The first native Linux scan is the remaining hardware validation step. Once that succeeds, the protocol library will be separated from the test harness and exposed through a dedicated SANE backend, a narrow udev rule, and then NAPS2.

## Production backend requirements

The final backend must not:

- hard-code `/dev/sg1`, `/dev/sg2`, USB bus or USB device numbers;
- add the user to the broad `disk` group;
- globally allow every PDT=0 disk to be treated as a scanner;
- modify the existing generic Avision backend in a way that affects unrelated devices;
- detach `usb-storage` permanently;
- require root for ordinary scanning.

It should match at least:

```text
USB VID:PID   0a38:0161
USB serial    <device-serial>, or a configurable model-wide match
SCSI vendor   IRIS
SCSI model    IRIScanExpress4
```

and expose a dedicated device name such as:

```text
iriscanexpress4:sg:/dev/sgX
```

The initial supported mode should remain the proven captured mode—300 dpi Color—until additional captures or controlled parameter experiments establish safe mappings for grayscale, black-and-white and other resolutions.

# Compatibility matrix

This table tracks independently tested IRIScan Express 4 units. Please submit a hardware report using the GitHub issue template rather than editing rows without evidence.

| USB ID | SCSI vendor/model | Revision | Distro / kernel | INQUIRY | Init | Paper transport | Polling | C3 image transfer | Complete scan |
|---|---|---|---|---|---|---|---|---|---|
| `0a38:0161` | `IRIS / IRIScanExpress4` | `0.11` | Ubuntu 26.04 LTS / kernel 7.0 series (reference system) | PASS | PASS | PASS | PASS | BLOCKED: repeatable `resid=78` | NOT YET |

## What to report

Please include:

- distro and version
- kernel (`uname -a`)
- `lsusb -d 0a38:0161`
- USB descriptors from the safe diagnostic bundle
- SCSI vendor/model/revision
- result of `tools/iriscan-safe-inquiry.sh`
- whether you ran an experimental scan intentionally
- exact C3 requested length/residual if applicable

Do not publish your scanner serial unless it is genuinely needed to diagnose a device-specific problem. Redact unrelated storage/device data from manually collected logs.

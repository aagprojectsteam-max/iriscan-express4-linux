# Safety and security

The experimental scan path uses raw `SG_IO` against a device that reports itself as SCSI peripheral type 0 (disk). Incorrect targeting could be dangerous.

The supplied scripts therefore:

- match USB VID/PID `0a38:0161`;
- verify SCSI vendor/model `IRIS` / `IRIScanExpress4`;
- derive `/dev/sgX` from sysfs instead of hard-coding it;
- refuse experimental operation if the related block device is mounted;
- keep standard INQUIRY diagnostics separate from vendor-command tests.

Do not bypass these checks when testing on real hardware.

# Safety and security

The experimental scan path uses raw `SG_IO` against a device that reports itself as SCSI peripheral type 0 (disk). Incorrect targeting could be dangerous.

The supplied scripts therefore:

- match USB VID/PID `0a38:0161`;
- verify SCSI vendor/model `IRIS` / `IRIScanExpress4`;
- derive `/dev/sgX` from sysfs instead of hard-coding it;
- refuse experimental operation if the related block device is mounted;
- keep standard INQUIRY diagnostics separate from vendor-command tests.

Do not bypass these checks when testing on real hardware.

## End-user installer trust boundary

The optional WinBoat downloader queries only the official `winboat-org/winboat` GitHub API, accepts one stable amd64 Debian asset under that repository's release URL, requires a valid GitHub-published SHA256 digest, and verifies the complete download before invoking `apt`.

The installer does not silently add a user to the `docker` group. That group is root-equivalent; when membership is missing, the user receives an explicit command and warning. The package has no maintainer script that edits WinBoat, starts containers, or changes USB/storage configuration.

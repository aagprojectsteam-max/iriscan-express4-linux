# C3 forensic work

The current blocker is a deterministic SG_IO residual of 78 bytes on vendor command C3 image reads. Successful status has been observed for both 65536-byte and 32768-byte requests, so changing the chunk size alone did not resolve or explain the result.

## Instrumented experiment

Before each C3 attempt, the native program fills the destination with a deterministic sentinel. It then records the request/address, residual and derived length, ioctl/SCSI/host/driver status, duration, sense metadata, changed-byte count, exact modification boundary, unchanged suffix, and FNV-1a hashes.

Logs use `C3_OBSERVATION` and `C3_MODIFICATION_BOUNDARY`. A payload byte can coincidentally equal its sentinel byte, so changed-byte counts are evidence—not a replacement transfer length. Private image content is not printed.

## Decision gate

Do not ignore `resid`, pad 78 bytes, concatenate retries, or over-request blindly. Compare repeatable Linux observations with a sanitized known-good Windows transfer and, where possible, kernel usb-storage/sg traces. A change is eligible only after it explains the accounting and produces a complete image without missing or shifted lines.

Native support stays experimental until two consecutive full scans, reconnect, dynamic discovery, and failure cleanup all pass.

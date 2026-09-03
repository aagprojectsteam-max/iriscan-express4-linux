# Development status

The experimental native Linux path has demonstrated the following on real hardware:

1. Exact USB/SCSI discovery.
2. Standard INQUIRY.
3. Replay of a large captured initialization sequence.
4. Captured 300 DPI color setup.
5. START accepted by the scanner.
6. Physical paper transport.
7. Repeated status polling.
8. Ready descriptor with width `2592`, plane-row count `240`, and a non-zero image-buffer address.
9. Entry into vendor command `C3` image reads.

Current blocker: on the tested Linux SG_IO/usb-storage path, C3 reads return `rc=0` while the kernel reports a deterministic residual of 78 bytes for both 65536-byte and 32768-byte requests. It remains to be proven whether the residual is a true missing-payload length or an unreliable transport accounting field for this vendor command.

The code now pre-fills every C3 request with a deterministic sentinel and logs SG status, sense metadata, exact modification boundaries, unchanged suffix length, and hashes. This instrumentation passes non-hardware CI; a controlled physical scan is required to collect new evidence.

No production-ready full-page native Linux scan has been confirmed yet.

No SANE backend is shipped. SANE development begins only after the native success gate is met.

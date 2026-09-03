# Contributing

## The most useful contribution: hardware reports

If you own an IRIScan Express 4, run:

```bash
bash tools/iriscan-diagnose.sh
```

Then open a **Hardware report** issue and attach the generated `.tar.gz`. Please review the bundle before uploading it. The diagnostic script redacts the USB serial by default.

## Experimental scanning

Only run `scripts/run-experimental-scan.sh` if you accept that it sends reverse-engineered vendor commands and moves paper. Keep the scanner's block device unmounted.

## Development rules

- Do not hard-code `/dev/sg0`, `/dev/sg1`, etc.
- Match the physical device through USB identity and sysfs ancestry.
- Do not globally relax SANE/libusb rules for all mass-storage devices.
- Preserve cleanup/RELEASE behavior on failure and signals.
- Do not redistribute vendor Windows binaries.
- New protocol claims should be backed by a capture, trace, or repeatable hardware test.

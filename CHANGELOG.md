# Changelog

## 0.3.0-ubuntu — 2026-09-03

- Added one obvious end-user Ubuntu installer package and Quick Start asset.
- Added guided `iriscan-setup`, safe official WinBoat download with GitHub SHA256 verification, `iriscan-doctor`, `iriscan-uninstall`, and the short `iriscan-support-bundle` command.
- Added clean-home package lifecycle coverage for install, idempotent reinstall, doctor, uninstall, repeated uninstall, and reinstall.
- Rewrote the README around the ordinary user's download and scan path.
- Documented exact official WinBoat and IRIS support sources and every unavoidable proprietary/GUI step.
- Preserved the native Linux path as experimental; no SANE or native-driver claim is made.

## 0.2.0-winboat — 2026-09-03

- Added a safe, idempotent WinBoat integration toolkit with dry-run, validation, timestamped backups, targeted removal, verification, and redacted support bundles.
- Added fixture tests covering compose mapping/list forms, preservation of unrelated QEMU arguments, duplicate prevention, dry-run, and rollback removal.
- Added a non-destructive Debian package and repeatable release-asset workflow.
- Reorganized the README around working-now WinBoat, experimental native Linux, and help-testing paths.
- Added lawful Windows driver/PnP/service verification and Error Code 2019 troubleshooting.
- Added C3 sentinel-buffer and SG status instrumentation without treating `resid=78` as solved.
- Added automated privacy and proprietary-binary checks.

## 0.1.0-research — 2026-09-03

- Published clean-room research repository for IRIScan Express 4 (`0a38:0161`).
- Added safe diagnostic and standard INQUIRY tools.
- Added captured protocol transcripts used by the experimental Linux SG_IO PoC.
- Added current experimental scanner source and image converter.
- Documented confirmed native milestones and the unresolved C3 `resid=78` blocker.
- Added GitHub issue templates and CI build checks.

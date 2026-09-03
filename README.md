# IRIScan Express 4 for Ubuntu

## I just want to scan

### Recommended method: Ubuntu + WinBoat + the official Windows driver

Native Linux scanning is not finished. Today, the supported practical method runs the official IRIS/Avision scanner software inside Windows through WinBoat.

Automated WinBoat setup targets **64-bit Ubuntu 24.04 or newer**. The computer also needs hardware virtualization, at least 4 GB RAM, and at least 32 GB free storage.

**Download this package:**

### [Download the Ubuntu installer (`.deb`)](https://github.com/aagprojectsteam-max/iriscan-express4-linux/releases/download/v0.3.0-ubuntu/iriscan-express4-ubuntu-installer_0.3.0_all.deb)

Then open a terminal in your Downloads folder:

```bash
sudo apt install ./iriscan-express4-ubuntu-installer_0.3.0_all.deb
iriscan-setup --install-winboat
```

After installing the package, you can alternatively open **IRIScan Express 4 Setup** from Ubuntu's application menu. **IRIScan Express 4 Doctor** is available there too.

The first command installs this project's guided setup and diagnostics. Package installation itself does not change WinBoat. The second command can install missing Docker/Compose/FreeRDP 3 Ubuntu packages, download the latest official amd64 WinBoat package, verify its GitHub-published SHA256, and install it after confirmation.

If setup says `DOCKER_ACCESS=ACTION_REQUIRED`, run the displayed `usermod` command and log out/in once. Docker-group membership is root-equivalent, so the installer explains this security-sensitive step instead of silently changing your account.

Next:

1. Launch WinBoat and complete its Windows setup.
2. Close WinBoat and run `iriscan-setup` again. Review and approve the one-line USB passthrough change.
3. Start WinBoat.
4. Inside Windows, install the official IRIS/Avision software from your licensed media or the [official IRIScan Express 4 support section](https://support.irislink.com/en-us/section/106-iriscan-express-4-iriscan-executive-4).
5. Scan with the official Windows Capture Tool.

This project cannot redistribute the proprietary Windows driver. It is required because native Linux image transfer is not yet complete. WinBoat itself is MIT-licensed but currently beta; its [official prerequisites](https://github.com/winboat-org/winboat#prerequisites) include an amd64 system, virtualization, sufficient RAM/storage, Docker with Compose v2, and FreeRDP 3. Docker Desktop and Podman USB passthrough are not supported by WinBoat.

Read the printable [Quick Start](docs/QUICKSTART.txt) for the complete installation and removal sequence.

## Check whether it is ready

```bash
iriscan-doctor
```

It reports:

```text
SCANNER_FOUND=YES/NO
USB_ACCESS=PASS/NOT_TESTED
BACKEND=WINBOAT_OFFICIAL_WINDOWS_DRIVER
WINBOAT=FOUND/NOT_FOUND
WINDOWS_PASSTHROUGH=CONFIGURED/NOT_CONFIGURED
READY_TO_SCAN=YES/NO
```

`READY_TO_SCAN=YES` means the observable Ubuntu/WinBoat side is ready. Driver installation and scanner detection must still be checked inside Windows.

If setup fails, create a privacy-redacted support archive:

```bash
iriscan-support-bundle
```

Review the archive, then attach it to a [WinBoat setup issue](https://github.com/aagprojectsteam-max/iriscan-express4-linux/issues/new?template=winboat-report.yml).

## Uninstall

Close WinBoat, then run as your normal user:

```bash
iriscan-uninstall
sudo apt remove iriscan-express4-ubuntu-installer
```

The first command previews and removes only this project's IRIScan QEMU argument, preserving every unrelated WinBoat setting. It creates a timestamped backup. The second removes the Ubuntu package.

## Troubleshooting

- **WinBoat not configured:** run `iriscan-setup --install-winboat`, launch WinBoat, complete Windows setup, close it, and rerun `iriscan-setup`.
- **Scanner not found:** connect the IRIScan Express 4 directly by USB and rerun `iriscan-doctor`.
- **WinBoat is running during setup:** shut it down normally so it cannot overwrite the compose edit, then rerun setup.
- **Windows Error Code 2019 / “Can not find the scanner”:** follow [Windows setup and physical-device verification](docs/WINDOWS-SETUP.md). A `ROOT\IMAGE` node alone is not proof of USB passthrough.
- **Need detailed logs:** run `iriscan-support-bundle`; it avoids unrelated disk data and redacts scanner serials, home paths, usernames, common credentials, and token shapes.

## Native Linux status

Native Linux support remains **experimental and is not installed by the end-user package**.

Confirmed research milestones:

- dynamic USB/SCSI device discovery and standard INQUIRY;
- captured 300 DPI Color initialization;
- paper transport and status polling;
- real image-buffer discovery.

Current blocker: vendor opcode `0xC3` returns successful SCSI/host/driver status with repeatable Linux `io.resid=78` behavior. The forensic implementation records sentinel-buffer boundaries, residuals, status, sense metadata, and hashes. It does not ignore or guess around the residual.

There is no SANE backend and no native `iriscan-express4_1.0.0_amd64.deb`. Native support will not be advertised until complete image acquisition, two scans, replug, cleanup, dynamic discovery, SANE, and a normal graphical scanning application all pass on real hardware.

## Developers and reverse engineering

This section is optional for normal users.

```bash
git clone https://github.com/aagprojectsteam-max/iriscan-express4-linux.git
cd iriscan-express4-linux
bash scripts/check.sh
```

The native experimental command sends reverse-engineered vendor commands and moves paper. Read [Testing](docs/TESTING.md), [Security](SECURITY.md), [protocol notes](docs/PROTOCOL.md), and [C3 forensics](docs/C3-FORENSIC.md) before using it.

The scanner is identified dynamically as USB `0a38:0161` plus SCSI vendor/model `IRIS / IRIScanExpress4`; `/dev/sgX` is never hard-coded. Public transcripts contain a serial placeholder, not a private device serial.

## Legal and privacy

This independent interoperability project is not affiliated with IRIS, Avision, Microsoft, or WinBoat. No proprietary vendor driver, DLL, executable, private capture, or scanned document is distributed. See [Privacy](docs/PRIVACY.md) and [License](LICENSE).

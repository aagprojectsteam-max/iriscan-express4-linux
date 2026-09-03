# v0.3.0-ubuntu release checklist

This is the ordinary-user Ubuntu release for the working WinBoat path. It is not a native Linux/SANE driver.

## Public download

- Tag: `v0.3.0-ubuntu`
- Title: `IRIScan Express 4 for Ubuntu v0.3.0`
- Primary asset: `iriscan-express4-ubuntu-installer_0.3.0_all.deb`
- Companion assets: `IRIScan-Express4-Ubuntu-QUICKSTART.txt` and `IRIScan-Express4-v0.3.0-SHA256SUMS.txt`

The GitHub-generated source archives remain available to developers but are not described as user downloads.

## Gates

```bash
bash scripts/check.sh
bash scripts/build-release.sh
cd dist
sha256sum -c IRIScan-Express4-v0.3.0-SHA256SUMS.txt
```

Required results:

- strict C build and protocol integrity pass;
- shell/Python syntax pass;
- WinBoat compose fixture tests pass;
- official-download metadata validation pass;
- package contains setup, doctor, uninstall, and support commands;
- package contains application-menu launchers and the offline Quick Start;
- extracted clean-home lifecycle passes install, second install, doctor, uninstall, second uninstall, and reinstall;
- package contains no maintainer scripts that modify WinBoat;
- privacy/proprietary-binary audit passes;
- release checksums pass locally and again after downloading the published assets.

## Honest status

Release notes and README must state:

- working path: Ubuntu → WinBoat → Windows → official IRIS/Avision driver;
- WinBoat is beta and requires its documented prerequisites;
- proprietary Windows software must be obtained lawfully and is not bundled;
- native C3 transfer remains unresolved;
- no native SANE backend or native production package exists.

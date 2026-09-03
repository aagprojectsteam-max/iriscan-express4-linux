# Public release artifacts

`v0.2.0-winboat` is the first practical Ubuntu-use release. Its working path uses WinBoat and the official Windows driver. Native Linux remains experimental.

Build the four public assets with:

```bash
bash scripts/build-release.sh
```

The `.deb` installs host-side commands only and has no post-install action. Binary artifacts belong on the GitHub Release and are ignored by Git; release notes and checksum instructions are committed here.

The historical `v0.1.0-research` release and checksum record remain available. Do not replace or relabel that history.

# Privacy / publication policy

Public repository artifacts should not contain:

- personal device serial numbers;
- user home-directory names;
- raw Windows driver packages or proprietary IRIS/Avision DLL/EXE files;
- full USB captures unless intentionally reviewed and sanitized;
- unrelated system logs.

The diagnostic tool redacts the USB serial by default.

`iriscan-setup` and `iriscan-uninstall` keep timestamped logs below the invoking user's XDG state directory (normally `.local/state/iriscan-express4`). They record status and the narrowly scoped compose diff, not the full compose file. The public support-bundle command additionally redacts usernames, home paths, serials, common credential fields, and token shapes; users should still review every archive before upload.

# Hardware notes

The tested IRIScan Express 4 enumerates as one USB interface:

- Class 8: Mass Storage
- Subclass 6: SCSI Transparent
- Protocol 0x50: Bulk-Only Transport
- Bulk IN endpoint 0x81
- Bulk OUT endpoint 0x02

Linux normally binds `usb-storage` and exposes both a block node and a SCSI generic node. Standard INQUIRY identifies:

```text
Vendor:   IRIS
Model:    IRIScanExpress4
Revision: 0.11 (tested unit)
PDT:      0
```

`/dev/sgX` is not stable across replug/reboot and must be discovered dynamically.

# Windows setup and verification

Use the official IRIS/Avision installer obtained from the original licensed media or the [official IRIScan Express 4 support section](https://support.irislink.com/en-us/section/106-iriscan-express-4-iriscan-executive-4). If your licensed download is no longer shown, use the conversation/contact option on that official support site. This project does not redistribute the proprietary package because no redistribution permission has been established.

## Install

1. Confirm host-side WinBoat verification passes and start Windows.
2. Install the official IRIScan Express 4 software as Administrator.
3. Reboot Windows if the official installer requires it.
4. Open the vendor Capture Tool and select IRIScan Express 4.

Depending on the package version, components can include `IRIScanExpress4.ds`, `IRIScanExpress4.dll`, `IRIScanExpress4_x64.dll`, `Capture Tool.exe`, `Avscan_n.dll`, `Advance.dll`, `SmartImage.dll`, and `Twdsm_n.dll`. Their presence is a software clue, not proof that the physical USB device reached Windows.

## Verify the physical device

Run PowerShell as Administrator:

```powershell
Get-PnpDevice -PresentOnly | Where-Object {
  $_.InstanceId -match 'VID_0A38&PID_0161'
} | Format-List Status,Class,FriendlyName,InstanceId

Get-PnpDevice -PresentOnly | Where-Object {
  $_.InstanceId -match 'VID_0A38&PID_0161'
} | Get-PnpDeviceProperty |
  Where-Object KeyName -match 'HardwareIds|Service|Driver' |
  Format-Table KeyName,Data -AutoSize

Get-Service -Name AVISION_WIA_Service,StiSvc |
  Format-Table Name,Status,StartType
```

Decisive PnP evidence contains `VID_0A38` and `PID_0161`. An instance ID beginning only with `ROOT\IMAGE\...` is a virtual/root imaging node; by itself it does not prove USB passthrough.

Confirm `AVISION_WIA_Service`, Windows Image Acquisition (`StiSvc`), the TWAIN data source, and vendor Capture Tool are available.

## Error Code 2019 / “Can not find the scanner”

Check in this order:

1. Ubuntu still lists `0a38:0161` and no host application owns it.
2. `iriscan-winboat-verify` reports the argument and container USB bus.
3. WinBoat was fully stopped and restarted after editing compose.
4. Windows shows a present device with `VID_0A38&PID_0161`, not only `ROOT\IMAGE`.
5. Both services above are healthy.
6. Matching x64/TWAIN/WIA components are installed.
7. Close competing scanning applications and reopen Capture Tool.

Do not pass unrelated USB devices, change storage mappings, globally detach `usb-storage`, or replace the Windows image.

## End-to-end acceptance

Scan and save one ordinary page, then a second page. Restart WinBoat normally and repeat detection. Until these physical checks succeed, host configuration is ready but end-to-end validation remains pending.

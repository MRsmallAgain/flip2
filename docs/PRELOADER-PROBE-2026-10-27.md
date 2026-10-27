# Preloader probe, 2026-10-27

Authorized read of this already-rooted TCL Flip 2 / Gflip6 (4058G), serial `ONTKKB9L7PEUX4Z5`. One handshake on USB port `1-2`. No unlock, no boot flash, no `neutron.img` write.

The phone was already unlocked and Magisk-rooted. This note does not change that, and it is not a reason to run the erase-gated slice on this device. Unlocking it would erase it.

## What was sent

115200 8N1. One bulk OUT of the 8-byte sequence `FASTBOOT` to MediaTek preloader `0e8d:2000` on port `1-2` only (`/dev/bus/usb/001/065`). Bootrom `0e8d:0003` was logged and not opened. Fastboot gadget `0e8d:201c` was not opened. A later preloader window during reboot was not sent another `FASTBOOT`.

Four opens of that node were `Permission denied` (`denied=1..4`) before udev caught up. The fifth open is the only one that transmitted. Counters: `opens=1 attempted=1 denied=4`.

## What came back

Three bulk IN reads: 5, 5, and 8 bytes. Together:

```text
52454144595245414459544f4f4254534146
READYREADYTOOBTSAF
```

That is `READY` + `READY` + `TOOBTSAF`. `TOOBTSAF` is the 8-byte `FASTBOOT` reversed. The first 8 bytes are `READYREA`, not `READYTOO`. Exit 99 (hard-stop, no retry, nothing else written) was the correct result for this probe.

The wizard string `READYTOOB` and the host confirm `READYTOO` do not match this reply. Fastboot still enumerated because the preloader acted on the OUT bytes. Enumeration was the operational signal. Do not treat `READYREADYTOOBTSAF` as a wizard success, and do not change the confirm parser so this phone continues into unlock or boot flash.

## After the handshake

Exactly one fastboot device. Read-only getvar:

| name | value |
|------|--------|
| version | 0.5 |
| unlocked | yes |
| product | gflip6 |
| serialno | ONTKKB9L7PEUX4Z5 |
| secure | no |

`fastboot reboot` returned OKAY in 0.050 s. USB adb came back authorized at 2026-10-27T11:22:38-04:00 as `1bbb:0c01`, serial `ONTKKB9L7PEUX4Z5`, model `4058G`. Uptime was about 2 minutes, so this was a reboot and not a userdata wipe. `flashing unlock` and `flash:boot` were not sent.

Installed udev rules file `/etc/udev/rules.d/51-android-flip2-adb.rules` was unchanged: sha256 `f56b9d80b4beda581d5b649f6957baf4f072f15826049501e6dcbe5b4450e187`, identical to `wizard/51-android-flip2-adb.rules`.

TCP `192.168.50.50:5555` was `unauthorized` after the reboot. USB adb stayed authorized. That is a phone-side prompt, not a host key replacement.

## Where this lives

`tools/flip2-preloader-probe.c` is the source that produced this result. It sends `FASTBOOT` once to port `1-2` / `0e8d:2000` and stops on any other non-empty reply. It does not reset the bus and does not send unlock or flash commands.

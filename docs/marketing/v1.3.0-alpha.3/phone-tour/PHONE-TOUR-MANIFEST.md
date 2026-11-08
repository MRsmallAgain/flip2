# Flip2 live phone tour — 2026-11-08

Captured on device **RWORPFDQUG4TNN9D** (4058G / Gflip6) via `scripts/phone-tour-screenshots.sh`.

## Highlights for marketing

| File | What it shows |
|------|----------------|
| `01-homescreen.png` | Launcher4 lock/home — soft keys (Notifications / Menu / Pairing) |
| `02-menu-grid.png` | 3×3 slots 1–9 (repo canonical — live MediaCenter screencap was blank on this host) |
| `03-tag-drawer.png` | Pixel Tag Drawer — search, List/Icons, installed apps |
| `18-tools-folder.png` | Tools folder (@tools) — Settings, Note, Calculator, etc. |
| `20-flipmouse-chrome-cursor.png` | **FlipMouse** — D-pad focus highlight in Chrome (Wikipedia tile) |
| `11-slot9-bouncy.png` / `21-bouncy-arkanoid.png` | Vector Pinball / Bouncy — D-pad game on slot 9 |
| `10-slot7-chrome.png` | Browser slot |
| `12-forkgram.png` | Forkgram Classic |
| `14-intertune.png` | Intertune (home-keys left, not on grid) |
| `15-newpipe.png` | NewPipe |
| `08-slot5-settings.png` | Settings |

## All captures

| # | File | Package / note |
|---|------|----------------|
| 01 | `01-homescreen.png` | HOME |
| 02 | `02-menu-grid.png` | `MediaCenterActivity` (file from `docs/screenshots/menu-grid.png`) |
| 03 | `03-tag-drawer.png` | `com.iwadjp.pixeltagdrawer` |
| 04 | `04-slot1-calculator.png` | Calculator |
| 05 | `05-slot2-mms.png` | Messages |
| 06 | `06-slot3-contacts.png` | Contacts |
| 07 | `07-slot4-gallery.png` | Gallery |
| 08 | `08-slot5-settings.png` | Settings |
| 09 | `09-slot6-camera.png` | **Poor** — `adb screencap` ~4 KB blank; capture camera manually on device |
| 10 | `10-slot7-chrome.png` | Chrome |
| 11 | `11-slot9-bouncy.png` | Bouncy |
| 12–13 | `12-forkgram.png`, `13-forkgram-chats.png` | Forkgram — redact chats before public use |
| 14 | `14-intertune.png` | Intertune |
| 15 | `15-newpipe.png` | NewPipe |
| 16 | `16-fdroid-basic.png` | F-Droid Basic |
| 17 | `17-vlc.png` | VLC |
| 18 | `18-tools-folder.png` | `ToolsNewActivity` |
| 19–20 | `19-flipmouse-chrome-idle.png`, `20-flipmouse-chrome-cursor.png` | FlipMouse toggle via `sendevent` KEY_MENU (139) hold 1.1s on `matrix-keypad` |
| 21 | `21-bouncy-arkanoid.png` | Bouncy again |
| 22 | `22-homescreen-final.png` | HOME |

## Re-run

```bash
adb devices   # one authorized Flip2
bash ~/flip2-marketing-2026-11/scripts/phone-tour-screenshots.sh
```

**FlipMouse on device:** hold upper-left soft key ~1s, release. Exit: `*`. Script uses root `sendevent` on `/dev/input/event2`.

**Menu grid:** activity `com.tim.flip2.launcher4/...MediaCenterActivity` or center **Menu** soft key.

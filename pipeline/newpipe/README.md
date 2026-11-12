# NewPipe patch — Flip 2 D-pad focus

NewPipe (`org.schabi.newpipe`) v0.27.7 (F-Droid `org.schabi.newpipe_1015.apk`) ships `NewPipeRecyclerView` and `FocusOverlayView` for TV-style focus, but on the Flip 2 keypad many users still see poor traversal compared to **Intertune** (Compose focus). This pipeline applies small smali tweaks so hardware D-pad can claim focus without waiting for a global focus-bridge APK.

## Benchmark (Intertune vs NewPipe)

| App | Mechanism |
| --- | --- |
| **Intertune** | Compose `FocusRequester`, root `setFocusable` / `setFocusableInTouchMode` — reference only |
| **NewPipe stock** | `NewPipeRecyclerView` focusable + `FOCUS_AFTER_DESCENDANTS`; `FocusOverlayView.setupFocusObserver` on `MainActivity` |
| **Gap on Flip 2** | Touch-mode default blocks D-pad until decor + list rows accept focus in touch mode |

## Patches

`newpipe-0.27.7-dpad.patch`:

| File | Change |
| --- | --- |
| `MainActivity.smali` | `onResume`: decor `setFocusableInTouchMode(true)` |
| `views/NewPipeRecyclerView.smali` | All three constructors: `setFocusableInTouchMode(true)` after `setFocusable(true)` |

## Usage

```sh
flip2 newpipe patch              # build from deploy/sources or device APK, install
flip2 newpipe patch --no-install # build and sign only → /tmp/newpipe-patch/
flip2 newpipe patch --uninstall  # once when switching from F-Droid signature (wipes data)
```

Or directly:

```sh
bash pipeline/newpipe/patch-newpipe.sh --apk pipeline/deploy/sources/org.schabi.newpipe_1015.apk
```

## Verify (device)

1. Home feed: DPAD moves between stream cards; OK opens detail.
2. Search: field and results reachable.
3. Compare feel with Intertune on the same network (parity bar is “good enough”, not pixel-identical).

## Catalog / hosted release

Wizard still pins **stock** F-Droid NewPipe until you:

1. Run `patch-newpipe.sh`, publish debug-signed APK (same package).
2. Bump `wizard/catalog.json` URL + `sha256` + `size`.
3. Regenerate `pins.json`.

Use `--uninstall` once when replacing F-Droid install with debug-signed build.

## Version pin

- **versionCode:** 1015  
- **versionName:** 0.27.7  
- Re-decode and regenerate patch after upstream bumps.

# Display density (DPI) on Flip2

Main panel: **240×320**, physical density **160** (`ro.sf.lcd_density`). Cover: **128×128** at **213** dpi.

## Recommended: `wm size 321x428` + launcher dimens + font scale

**`adb shell wm size 321x428`** (logical ~1.34× vs stock) gives more room without the status-bar breakage seen at **`wm density 180`**. Pair it with:

| Layer | What |
|-------|------|
| **Launcher4 menu** | `launcher-overlay/res/values/dimens.xml` — scaled `allapp_*` / `toolapp_*` / `widget_big_font_size`; merged at **`flip2 launcher4 build`** |
| **System UI text** | **`flip2 display font 1.15`** (adjust 1.0–1.2; **`flip2 display font reset`** to undo) |

**Undo size:** `adb shell wm size reset`  
**Re-apply size after reboot:** size override may not persist — re-run size or add a boot script if you want it permanent.

## Per-app DPI (Telegram, Pixel Tag Drawer, …)

**Retail Android 11 (API 30) does not let you set a different DPI per installed app** the way Android 12+ can with `am compat` density overrides.

On this build we confirmed:

- `am compat enable …` → *Cannot override a change on a non-debuggable app and user build*
- `wm density` → **global only** (all apps + launcher)
- `am screen-compat on <package>` → legacy letterboxing for apps that declare fixed screen sizes; **not** the same as choosing 120 vs 180 dpi for Telegram

**Packages you asked about:**

| App | Package |
|-----|---------|
| Forkgram Classic (menu slot 2) | `org.forkgram.classic` — F-Droid **717607** (armeabi-v7a); **717608** is arm64-only and fails on Flip2 |
| Telegram (web APK, optional) | `org.telegram.messenger.web` |
| Pixel Tag Drawer | `com.iwadjp.pixeltagdrawer` (system via `flip2 tagdrawer install`) |

### What actually helps

1. **In-app settings** — Telegram: Settings → Chat Settings → Text Size (and similar). Pixel Tag Drawer: check its own display/font options if any.
2. **Global display size** — `flip2 display density <dpi>` or **Settings → Display → Font size / Display size** (TCL). Affects **everything**, including Launcher4. Reboot or force-stop heavy apps after big changes.
3. **Screen compatibility mode** — `flip2 display compat on <package>` — only useful if an app mis-detects the small screen; may add padding/scale, not fine DPI control.
4. **System font scale** — `settings put system font_scale 1.15` (1.0 = default). System-wide, not per-app.

### Global density examples (240×320 panel)

Higher dpi → UI looks **smaller** (more fits on screen). Lower dpi → **larger** touch targets and text.

| Goal | Try (temporary) |
|------|------------------|
| Slightly larger UI | `flip2 display density 140` |
| Stock | `flip2 display density reset` or `160` |
| Slightly smaller / more content | `flip2 display density 180` |

Always **`flip2 display density reset`** if the phone becomes awkward to use.

### TCL status bar / notification counter (do not use 180 globally)

On this Gflip6 build, **`wm density` overrides other than 160** (e.g. **180**) often break **SystemUI / the notification shade**: the bar scales badly and the **notification alert counter is clipped**. That is fixed by **`flip2 display density reset`**. Prefer **160** for daily use and scale **Telegram** via in-app text size + **`flip2 display compat on org.telegram.messenger.web`** if needed—not global 180.

### Future / image build

True per-app `densityDpi` overrides need **userdebug** or a **custom framework** hook (or repackaging APKs with `res/values-sw*` / manifest `compatible-screens` hacks). For a production Flip2 image, document chosen **global** density and in-app text sizes instead.

## Phantom bottom bar (`flip2 navoverlay`)

At `wm size 321x428` most apps painted a **30px black strip over the bottom edge** (clipped the Forkgram chat input in half, plus the stock Messages app). Root causes, both fixed:

1. **JRD decor menu bar** — this ROM adds `decor_menu_bar` (android.widget.MenuBar) to window decor: 30dp tall, `?navigationBarColor` background, empty in apps without menu items ⇒ black. Fixed by **RRO overlaying `framework-res layout/menu_bar(.xml)` (+ `_dish`) with `layout_height=0`**, shipped at `/product/overlay/Flip2NavOverlay.apk` via Magisk module `flip2_nav_overlay`.
2. **Flip2 Null Keyboard ≤ v1.6** — IMS window measured `321×54` and a show/hide race left `contentTopInsets≈30`, which apps cached as keyboard height. v1.7+ pins the IME window to **h=0**, reports `contentTopInsets=0/visibleTopInsets=0`, and does not cancel shows.

Data-installed overlays targeting `android` are filtered (`STATE_NO_IDMAP`, signature policy) — must go through `/product/overlay` (Magisk module). CLI: **`flip2 navoverlay {build|install|status|rollback}`** (`rollback` = remove module + reboot).

Hardware ⌫: the keypad has no delete key — **backspace emits `KEY_HELP`**, handled as delete by the null IME (v1.8+).

See also: `flip2 display help`, [CUSTOMIZATION.md](CUSTOMIZATION.md).

#!/system/bin/sh
# flip2 one-shot installer (service.sh). Runs as root on first boot after the
# zip is flashed via the Magisk app. Installs user APKs, unpacks the flip2
# module payloads (full flavor), applies baked settings, writes the de-root
# helper to /data/local/flip2, then marks itself for removal.

MOD=${0%/*}
[ -d "$MOD/payload" ] || MOD=/data/adb/modules/flip2_installer
LOG=/cache/flip2-installer.log
DONE=/data/local/flip2/.installer-done
STAGE=/data/local/flip2
SELF=flip2_installer
BB=/data/adb/magisk/busybox

exec >>"$LOG" 2>&1
echo "=== flip2 installer $(date) ==="

if [ -f "$DONE" ]; then echo "already done, skipping"; exit 0; fi
if [ ! -d "$MOD/payload" ]; then echo "no payload found, aborting"; exit 0; fi

FLAVOR=$(cat "$MOD/payload/data/flavor.txt" 2>/dev/null || echo full)
echo "flavor: $FLAVOR"
mkdir -p "$STAGE"

# --- wait for pm (system_server is not ready this early in boot) -----------
i=0
until pm list packages >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -ge 30 ] && break
  sleep 2
done

# --- user APKs -------------------------------------------------------------
# pm cannot read files under /data/adb — copy to /data/local/tmp first.
if [ -f "$MOD/payload/data/apks.txt" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    f=${line%% *}
    pkg=${line#* }
    cp "$MOD/payload/apks/$f" "$STAGE/$f"
    chmod 644 "$STAGE/$f"
    if pm install -r "$STAGE/$f" >/dev/null 2>&1; then
      echo "installed: $pkg"
    else
      echo "FAILED to install: $pkg ($f)"
    fi
    rm -f "$STAGE/$f"
  done < "$MOD/payload/data/apks.txt"
fi

# --- External APKs: downloaded at install time, never bundled ---------------
# forkgram (GitHub release) and Material Files (F-Droid direct URL) bake into
# payload/data/external-apks.txt as "<package>|<url>" lines.
if [ -f "$MOD/payload/data/external-apks.txt" ]; then
  while IFS='|' read -r pkg url; do
    [ -n "$pkg" ] && [ -n "$url" ] || continue
    if pm list packages 2>/dev/null | grep -q "^package:$pkg$"; then
      echo "$pkg already installed"
      continue
    fi
    f=$STAGE/$pkg.apk
    if [ -x "$BB" ] && "$BB" wget -O "$f" "$url" && [ -s "$f" ]; then
      if pm install -r "$f" >/dev/null 2>&1; then
        echo "installed: $pkg"
        rm -f "$f"
      else
        echo "FAILED to install $pkg (kept at $f)"
      fi
    else
      echo "$pkg download failed (Wi-Fi connected?). Retry later:"
      echo "  sh $STAGE/install-$pkg.sh"
      {
        echo '#!/system/bin/sh'
        echo "# Retry: download + install $pkg (needs Wi-Fi; run via adb shell)."
        echo "URL=$url"
        echo "PKG=$pkg"
        echo 'B=/data/adb/magisk/busybox'
        echo '[ -x "$B" ] || { echo "no Magisk busybox"; exit 1; }'
        echo '"$B" wget -O /data/local/flip2/$PKG.apk "$URL" \\'
        echo '  && pm install -r /data/local/flip2/$PKG.apk'
        echo '  && rm -f /data/local/flip2/$PKG.apk'
      } > "$STAGE/install-$pkg.sh"
      chmod 755 "$STAGE/install-$pkg.sh"
    fi
  done < "$MOD/payload/data/external-apks.txt"
fi

# --- flip2 Magisk modules (full flavor only) -------------------------------
if [ "$FLAVOR" = full ] && [ -f "$MOD/payload/data/modules.txt" ]; then
  # Stop the running FlipMouse supervisor + daemon first: unzip cannot replace
  # the executing mouse binary (Text file busy).
  pkill -f 'FlipMouse/service.sh' 2>/dev/null
  pkill -f 'FlipMouse/mouse' 2>/dev/null
  sleep 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    mid=${line%% *}
    f=${line#* }
    T=/data/adb/modules/$mid
    mkdir -p "$T"
    if unzip -o "$MOD/payload/modules/$f" -d "$T/" >/dev/null 2>&1; then
      echo "module placed: $mid (takes effect at next boot)"
    else
      echo "FAILED to unpack module: $mid"
    fi
  done < "$MOD/payload/data/modules.txt"
  # Magisk 25.2 stages CLI-installed modules until reboot; in-place unpack
  # works but nothing starts FlipMouse's daemon until service time — start it
  # now (same treatment as pipeline/flipmouse/scripts/ondevice-install.sh).
  FM=/data/adb/modules/FlipMouse
  if [ -x "$FM/mouse" ]; then
    rm -f "$FM/update"
    chmod 755 "$FM/mouse" "$FM/service.sh" 2>/dev/null
    chmod 644 "$FM/module.prop" 2>/dev/null
    nohup sh "$FM/service.sh" </dev/null >/dev/null 2>&1 &
    echo "FlipMouse daemon started"
  fi
fi

# --- baked settings / appops / permissions --------------------------------
apply_file() {
  [ -f "$1" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    eval "$line" || echo "FAILED: $line"
  done < "$1"
}
apply_file "$MOD/payload/data/settings.txt"
apply_file "$MOD/payload/data/appops.txt"
apply_file "$MOD/payload/data/permissions.txt"

# --- default HOME ----------------------------------------------------------
if cmd package set-home-activity com.tim.flip2.launcher4/com.android.launcher3.Launcher >/dev/null 2>&1; then
  echo "HOME set to launcher4"
else
  echo "could not set HOME automatically; pick Launcher4 when Android asks"
fi

# --- Vosk models (optional, user-supplied URLs, never bundled) -------------
if [ -f "$MOD/payload/data/vosk-urls.txt" ]; then
  NULL_PKG=com.tim.flip2.nullkeyboard
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name=${line%% *}
    url=${line#* }
    echo "fetching vosk model: $name"
    T=$STAGE/vosk-$name.zip
    if [ -x "$BB" ] && "$BB" wget -O "$T" "$url" && [ -s "$T" ]; then
      D=/data/data/$NULL_PKG/files/vosk/$name
      mkdir -p "$D"
      unzip -o "$T" -d "$D/" >/dev/null 2>&1 || "$BB" unzip -o "$T" -d "$D/" >/dev/null 2>&1
      rm -f "$T"
      OWNER=$(stat -c %u:%g /data/data/$NULL_PKG 2>/dev/null)
      [ -n "$OWNER" ] && chown -R "$OWNER" /data/data/$NULL_PKG/files/vosk
      restorecon -RF /data/data/$NULL_PKG/files/vosk 2>/dev/null
      echo "vosk $name placed"
    else
      echo "vosk $name download failed; push manually (see README)"
      rm -f "$T"
    fi
  done < "$MOD/payload/data/vosk-urls.txt"
else
  echo "Vosk models not bundled. Add URLs with 'flip2 installer pack --vosk-url en=<url> --vosk-url uk=<url>' or push manually."
fi

# --- Whisper ggml models (optional, user-supplied URLs, never bundled) ------
if [ -f "$MOD/payload/data/whisper-urls.txt" ]; then
  NULL_PKG=com.tim.flip2.nullkeyboard
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name=${line%% *}
    url=${line#* }
    echo "fetching whisper model: $name"
    T=$STAGE/whisper-$name.bin
    if [ -x "$BB" ] && "$BB" wget -O "$T" "$url" && [ -s "$T" ]; then
      D=/data/data/$NULL_PKG/files/whisper/$name
      mkdir -p "$D"
      mv "$T" "$D/model.bin"
      OWNER=$(stat -c %u:%g /data/data/$NULL_PKG 2>/dev/null)
      [ -n "$OWNER" ] && chown -R "$OWNER" /data/data/$NULL_PKG/files/whisper
      restorecon -RF /data/data/$NULL_PKG/files/whisper 2>/dev/null
      echo "whisper $name placed"
    else
      echo "whisper $name download failed; push manually (see README)"
      rm -f "$T"
    fi
  done < "$MOD/payload/data/whisper-urls.txt"
else
  echo "Whisper models not bundled (Vosk will be used). Add URLs with 'flip2 installer pack --whisper-url en=<url>' or push manually."
fi

# --- de-root helper + instructions -----------------------------------------
cp "$MOD/payload/deroot.sh" "$STAGE/deroot.sh"
chmod 755 "$STAGE/deroot.sh"

echo "----------------------------------------"
echo "flip2 install complete ($FLAVOR flavor)."
echo "De-root later with: sh $STAGE/deroot.sh [--uninstall-apks]"
if [ "$FLAVOR" = clean ]; then
  echo "clean flavor: nothing root-dependent was installed; once Magisk is"
  echo "removed (app -> Uninstall -> Restore Images) everything here stays."
fi

# --- stamp done + self-remove ---------------------------------------------
touch "$DONE"
touch "$MOD/remove"
rm -rf "/data/adb/modules_update/$SELF" 2>/dev/null
echo "installer module marked for removal at next boot"
echo "=== done ==="
exit 0

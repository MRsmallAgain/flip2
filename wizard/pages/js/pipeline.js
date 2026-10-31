// Builds the push set from the verified downloads and pushes it over ADB,
// then runs /data/local/flip2/install.sh and mirrors its output to the log.
//
// Layout of the published installer zip (verified by unzip -l):
//   payload/modules/{flip2_nav_overlay,flip2_keypad_backspace,FlipMouse,
//     flip2_pixel_tag_drawer,flip2_launcher_overlay}-magisk.zip  (module zips)
//   payload/apks/{launcher4.apk,nullkeyboard.apk}
// The Tag Drawer module zip is rebuilt here so it embeds the fresh F-Droid
// APK (system/app/PixelTagDrawer/PixelTagDrawer.apk — byte-size identical
// to the catalog's com.iwadjp.pixeltagdrawer_7.apk, so the swap is drop-in).
//
// install.sh expects exactly these names in /data/local/flip2/incoming/:
//   5 module zips, launcher4.apk nullkeyboard.apk forkgram.apk intertune.apk
//   bouncy.apk materialfiles.apk ggml-tiny-q5_1.bin
//   vosk-model-small-en-us-0.15.zip vosk-model-small-uk-v3-nano.zip
// plus install.sh itself at /data/local/flip2/install.sh.

var INCOMING = '/data/local/flip2/incoming/';
var INSTALL_SH_REMOTE = '/data/local/flip2/install.sh';

function pushPayloadBytes(raw, label) {
  if (raw == null) throw new Error('push set missing bytes for ' + (label || '(unknown)'));
  if (raw instanceof Uint8Array) return raw;
  if (raw instanceof ArrayBuffer) return new Uint8Array(raw);
  if (ArrayBuffer.isView(raw)) {
    return new Uint8Array(raw.buffer, raw.byteOffset, raw.byteLength);
  }
  throw new Error('push set has invalid data for ' + (label || '(unknown)'));
}

var PIPE = {
  // files: map of catalog id -> Uint8Array (verified contents).
  // componentIds: optional. When it lists headwind, headwind.apk is added.
  // Omitted means today's base push (no Headwind). requiredIncoming is unchanged.
  // Returns a map remoteName -> Uint8Array ready to push.
  buildPushSet: function (files, componentIds) {
    var M = typeof PUSH_MANIFEST !== 'undefined' ? PUSH_MANIFEST : null;
    if (!M) throw new Error('PUSH_MANIFEST missing — run pipeline/wizard/gen-pipeline-js.sh');
    var installer = fflate.unzipSync(files['installer-full']);
    var out = {};
    var i, name, path;
    for (i = 0; i < M.installerModulePaths.length; i++) {
      path = M.installerModulePaths[i];
      if (!installer[path]) throw new Error('installer zip is missing ' + path);
      name = path.split('/').pop();
      out[name] = installer[path];
    }
    for (i = 0; i < M.installerApkPaths.length; i++) {
      path = M.installerApkPaths[i];
      if (!installer[path]) throw new Error('installer zip is missing ' + path);
      name = path.split('/').pop();
      out[name] = installer[path];
    }

    // Tag Drawer: rebuild the module zip around the fresh F-Droid APK.
    var tdPath = M.tagDrawerModulePath;
    var td = fflate.unzipSync(installer[tdPath]);
    var tdEntry = M.tagDrawerApkEntry;
    if (!td[tdEntry]) throw new Error('Tag Drawer zip is missing ' + tdEntry);
    td[tdEntry] = files['tagdrawer'];
    out[tdPath.split('/').pop()] = fflate.zipSync(td);

    if (M.wallpaperPath && installer[M.wallpaperPath]) {
      out['flip2-wallpaper.png'] = installer[M.wallpaperPath];
    }

    var renames = M.catalogRenames;
    for (var catId in renames) {
      if (!Object.prototype.hasOwnProperty.call(renames, catId)) continue;
      if (!files[catId]) throw new Error('catalog file missing: ' + catId);
      out[renames[catId]] = files[catId];
    }

    var need = M.requiredIncoming;
    for (i = 0; i < need.length; i++) {
      if (!out[need[i]]) throw new Error('push set incomplete: ' + need[i]);
    }

    // Headwind is not part of requiredIncoming. A base push omits it.
    // Managed lists the headwind component and must include the pinned APK.
    var wantHeadwind = false;
    if (componentIds && componentIds.length) {
      for (i = 0; i < componentIds.length; i++) {
        if (componentIds[i] === 'headwind') wantHeadwind = true;
      }
    }
    var wantWhere = false;
    if (componentIds && componentIds.length) {
      for (i = 0; i < componentIds.length; i++) {
        if (componentIds[i] === 'where') wantWhere = true;
      }
    }
    if (wantHeadwind) {
      if (!files['headwind-launcher']) throw new Error('catalog file missing: headwind-launcher');
      out['headwind.apk'] = files['headwind-launcher'];
    }
    if (wantWhere) {
      if (!files['where-app']) throw new Error('catalog file missing: where-app');
      out['where.apk'] = files['where-app'];
    }
    for (name in out) {
      if (!Object.prototype.hasOwnProperty.call(out, name)) continue;
      out[name] = pushPayloadBytes(out[name], name);
    }
    return out;
  },

  // pushSet: map name -> Uint8Array. Runs install.sh at the end. onLog gets
  // every progress and script line; stops on the first FAIL line and rejects
  // so main.js can offer Retry.
  pushAndInstall: function (pushSet, installSh, onLog) {
    var seq = Promise.resolve();
    var names = Object.keys(pushSet);
    var done = 0;
    names.forEach(function (nm) {
      seq = seq.then(function () {
        var u8 = pushPayloadBytes(pushSet[nm], nm);
        onLog('push ' + nm + ' (' + Math.round(u8.length / 1024) + ' KiB)…');
        return ADB.pushFile(INCOMING + nm, '0644', u8, null)
          .then(function () { done++; onLog('OK: pushed ' + nm + ' (' + done + '/' + names.length + ')'); });
      });
    });
    seq = seq.then(function () {
      onLog('push install.sh');
      return ADB.pushFile(INSTALL_SH_REMOTE, '0755', installSh, null);
    });
    seq = seq.then(function () {
      onLog('running install.sh as root…');
      var failed = null;
      return ADB.shell('sh ' + INSTALL_SH_REMOTE, function (line) {
        onLog(line);
        if (/^FAIL:/.test(line)) failed = line;
      }).then(function () {
        if (failed) throw new Error(failed);
      });
    });
    return seq;
  },

  // verify.sh runs as root too; mirrors SUMMARY and rejects on exit-failure
  // signaled by a RETRY line.
  verify: function (verifySh, onLog) {
    return ADB.pushFile('/data/local/flip2/verify.sh', '0755', verifySh, null)
      .then(function () {
        var failed = null;
        return ADB.shell('su -c "sh /data/local/flip2/verify.sh"', function (line) {
          onLog(line);
          if (/^FAIL:/.test(line)) failed = line;
        }).then(function () {
          if (failed) throw new Error(failed);
        });
      });
  },

  // Clean incoming/ once install has fully succeeded (install.sh keeps it
  // for Retry until this runs).
  cleanup: function (onLog) {
    return ADB.shell('rm -rf /data/local/flip2/incoming/*', function (line) { onLog(line); })
      .then(function () { onLog('OK: cleaned incoming/'); });
  },

  // Companion: host adb push (avoids WebUSB sync: timeout on Linux).
  // profileText, when set, is written to /data/local/flip2/profile.list after
  // prepare and before any incoming file. Omitting it keeps today's base push.
  // A missing writer is a hard stop: installing managed without the list
  // would skip Headwind.
  hostPushAndInstall: function (pushSet, installSh, onLog, profileText, onPhase) {
    var N = window.FLIP2_NATIVE;
    if (!N || !N.wizardHostPrepare) {
      return Promise.reject(new Error('host adb install requires Flip 2 Companion'));
    }
    if (profileText && !N.wizardHostWriteProfile) {
      return Promise.reject(new Error('writing the profile list requires Flip 2 Companion'));
    }
    var names = Object.keys(pushSet);
    var done = 0;
    function phase(text) {
      if (typeof onPhase === 'function') onPhase(text);
    }
    return N.wizardHostPrepare().then(function () {
      var seq = Promise.resolve();
      if (profileText) {
        seq = seq.then(function () {
          phase('writing profile.list…');
          onLog('write profile.list');
          return N.wizardHostWriteProfile({ text: profileText }).then(function () {
            onLog('OK: wrote profile.list');
          });
        });
      }
      names.forEach(function (nm, i) {
        seq = seq.then(function () {
          phase('pushing file ' + (i + 1) + ' of ' + names.length + ': ' + nm + '…');
          var raw = pushPayloadBytes(pushSet[nm], nm);
          onLog('push ' + nm + ' (' + Math.round(raw.length / 1024) + ' KiB)…');
          var bin = '';
          for (var j = 0; j < raw.length; j++) bin += String.fromCharCode(raw[j]);
          var b64 = btoa(bin);
          return N.wizardHostPushOne({ name: nm, dataBase64: b64 }).then(function () {
            done++;
            onLog('OK: pushed ' + nm + ' (' + done + '/' + names.length + ')');
          });
        });
      });
      return seq.then(function () {
        phase('running install.sh as root. Output appears when the script finishes.');
        onLog('running install.sh as root…');
        return N.wizardHostRunInstall({ installSh: installSh });
      }).then(function (r) {
        if (r.lines) r.lines.forEach(onLog);
        if (!r.ok) throw new Error(r.error || 'install failed');
        if (r.warnings) r.warnings.forEach(function (w) { onLog('note: ' + w); });
      });
    });
  },

  hostCleanup: function (onLog) {
    var N = window.FLIP2_NATIVE;
    if (!N || !N.wizardHostCleanup) return Promise.resolve();
    return N.wizardHostCleanup().then(function (r) {
      if (r.lines) r.lines.forEach(onLog);
      if (r.warning) onLog('note: cleanup non-fatal — ' + r.warning);
    });
  },

  hostVerify: function (verifySh, onLog) {
    var N = window.FLIP2_NATIVE;
    if (!N || !N.wizardHostVerify) {
      return Promise.reject(new Error('host adb verify requires Flip 2 Companion'));
    }
    return N.wizardHostVerify({ verifySh: verifySh }).then(function (r) {
      if (r.lines) r.lines.forEach(onLog);
      if (!r.ok) throw new Error(r.error || 'verify failed');
    });
  }
};

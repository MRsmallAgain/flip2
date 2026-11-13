// Builds the push set from the verified downloads and pushes it over ADB,
// then runs install.sh as root and mirrors its output to the log.
//
// Layout of the published installer zip (verified by unzip -l):
//   payload/modules/{flip2_nav_overlay,flip2_keypad_backspace,FlipMouse,
//     flip2_pixel_tag_drawer,flip2_launcher_overlay}-magisk.zip  (module zips)
//   payload/apks/{launcher4.apk,nullkeyboard.apk,…} — may include prefetched
//   forkgram.apk materialfiles.apk when host sources/ were bundled at pack time
// The Tag Drawer module zip is rebuilt here so it embeds the fresh F-Droid
// APK (system/app/PixelTagDrawer/PixelTagDrawer.apk — byte-size identical
// to the catalog's com.iwadjp.pixeltagdrawer_7.apk, so the swap is drop-in).
//
// install.sh expects exactly these names in its incoming directory:
//   5 module zips, launcher4.apk nullkeyboard.apk forkgram.apk intertune.apk
//   bouncy.apk materialfiles.apk … sherpa *.tar.bz2 (see push-manifest.js requiredIncoming)
//
// Paths come from DEVICE_PATHS (pages/js/device-paths.js, generated from
// pipeline/wizard/device-paths.json). The browser cannot write into the stage
// root: adbd's shell user is denied file creation there by SELinux, even at
// mode 0777. So the page stages into a shell-writable directory and
// install.sh — already root — ingests it with `install -m`.
var DP = typeof DEVICE_PATHS !== 'undefined' ? DEVICE_PATHS : null;

/** Android /system/bin/sh breaks on CRLF (syntax error on `in`, empty paths). */
function normalizeDeviceShellText(text) {
  return String(text == null ? '' : text).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

/** Script and list text as bytes: ADB.pushFile takes bytes, never a string. */
function textBytes(text) {
  var s = normalizeDeviceShellText(text);
  if (typeof TextEncoder !== 'undefined') return new TextEncoder().encode(s);
  var out = new Uint8Array(s.length);
  for (var i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 255;
  return out;
}

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
    var slimM = typeof PUSH_MANIFEST_SLIM !== 'undefined' ? PUSH_MANIFEST_SLIM : null;
    var catId = slimM && files['installer-slim'] ? 'installer-slim' : (M.installerCatalogId || 'installer-full');
    if (!files[catId] && files['installer-full']) catId = 'installer-full';
    var manifest = (catId === 'installer-slim' && slimM) ? slimM : M;
    var installer = fflate.unzipSync(files[catId]);
    var out = {};
    var i, name, path;
    for (i = 0; i < manifest.installerModulePaths.length; i++) {
      path = manifest.installerModulePaths[i];
      if (!installer[path]) throw new Error('installer zip is missing ' + path);
      name = path.split('/').pop();
      out[name] = installer[path];
    }
    for (i = 0; i < manifest.installerApkPaths.length; i++) {
      path = manifest.installerApkPaths[i];
      if (!installer[path]) throw new Error('installer zip is missing ' + path);
      name = path.split('/').pop();
      out[name] = installer[path];
    }
    var sherpaPaths = manifest.installerSherpaPaths;
    if (sherpaPaths) {
      for (i = 0; i < sherpaPaths.length; i++) {
        path = sherpaPaths[i];
        if (!installer[path]) throw new Error('installer zip is missing ' + path);
        name = path.split('/').pop();
        out[name] = installer[path];
      }
    }

    // Tag Drawer: rebuild the module zip around the fresh F-Droid APK.
    var tdPath = manifest.tagDrawerModulePath;
    var td = fflate.unzipSync(installer[tdPath]);
    var tdEntry = manifest.tagDrawerApkEntry;
    if (!td[tdEntry]) throw new Error('Tag Drawer zip is missing ' + tdEntry);
    td[tdEntry] = files['tagdrawer'];
    out[tdPath.split('/').pop()] = fflate.zipSync(td);

    if (manifest.wallpaperPath && installer[manifest.wallpaperPath]) {
      out['flip2-wallpaper.png'] = installer[manifest.wallpaperPath];
    }

    var renames = manifest.catalogRenames;
    var dest;
    var renameId;
    for (renameId in renames) {
      if (!Object.prototype.hasOwnProperty.call(renames, renameId)) continue;
      dest = renames[renameId];
      if (out[dest]) continue; // installer zip already supplied stable name (e.g. prefetch bundle)
      if (!files[renameId]) throw new Error('catalog file missing: ' + renameId);
      out[dest] = files[renameId];
    }

    var wantSherpaEn = false;
    var wantSherpaUk = false;
    if (componentIds && componentIds.length) {
      for (i = 0; i < componentIds.length; i++) {
        if (componentIds[i] === 'sherpa-en') wantSherpaEn = true;
        if (componentIds[i] === 'sherpa-uk') wantSherpaUk = true;
      }
    }
    var need = manifest.requiredIncoming ? manifest.requiredIncoming.slice() : [];
    if (wantSherpaEn || wantSherpaUk) {
      var withVoices = manifest.requiredIncomingWithVoices;
      if (withVoices) need = withVoices.slice();
      else {
        if (wantSherpaEn) need.push('sherpa-onnx-streaming-zipformer-en-20M-2023-02-17-mobile.tar.bz2');
        if (wantSherpaUk) need.push('sherpa-onnx-nemo-fast-conformer-transducer-be-de-en-es-fr-hr-it-pl-ru-uk-20k-int8.tar.bz2');
      }
    }
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

  // ADB.shell() resolves when the remote stream closes and never reports the
  // exit status, so a fire-and-forget mkdir or rm logs OK even after a
  // Permission denied. Every state-changing step echoes "<marker>:$?" and is
  // rejected unless the marker comes back with 0.
  shellChecked: function (cmd, marker, onLog) {
    var rc = null;
    var tag = marker + ':';
    return ADB.shell(cmd + ' 2>&1; echo "' + tag + '$?"', function (line) {
      if (line == null) return;
      var at = line.lastIndexOf(tag);
      var tail = at >= 0 ? line.slice(at + tag.length) : '';
      if (at >= 0 && /^[0-9]+$/.test(tail)) { rc = parseInt(tail, 10); return; }
      if (line) onLog(line);
    }).then(function () {
      if (rc === null) throw new Error('no exit status from: ' + cmd);
      if (rc !== 0) throw new Error('exit ' + rc + ': ' + cmd);
    });
  },

  // pushSet: map name -> Uint8Array. Runs install.sh at the end. onLog gets
  // every progress and script line; stops on the first FAIL line and rejects
  // so main.js can offer Retry. onPhase, when given, gets the same short
  // progress sentences the host path emits, so both paths drive the strip.
  pushAndInstall: function (pushSet, installSh, onLog, profileText, onPhase) {
    if (!DP) {
      return Promise.reject(new Error('DEVICE_PATHS missing — run pipeline/wizard/gen-pipeline-js.sh'));
    }
    function phase(text) {
      if (typeof onPhase === 'function') onPhase(text);
    }
    // adbd's shell user cannot create files under the stage root, so the page
    // prepares the shell-writable staging area and install.sh ingests it.
    phase('preparing staging area…');
    onLog('prepare staging area…');
    var seq = PIPE.shellChecked(
      'rm -rf ' + DP.shellStaging + ' 2>/dev/null; mkdir -p ' + DP.shellStagingIncoming,
      'STAGING', onLog
    ).then(function () { onLog('OK: staging area ready (' + DP.shellStaging + ')'); });
    // profile.list is what makes Arcade install Arcade and Base install Base;
    // without it install.sh treats every component as wanted.
    if (profileText) {
      seq = seq.then(function () {
        var lines = String(profileText).split('\n').filter(function (l) { return l.trim(); });
        onLog('push profile.list (' + lines.length + ' components)');
        return ADB.pushFile(DP.shellStagingProfileList, '0644', textBytes(profileText), null)
          .then(function () { onLog('OK: pushed profile.list'); });
      });
    }
    var names = Object.keys(pushSet);
    var done = 0;
    names.forEach(function (nm) {
      seq = seq.then(function () {
        phase('pushing file ' + (done + 1) + ' of ' + names.length + ': ' + nm + '…');
        var u8 = pushPayloadBytes(pushSet[nm], nm);
        onLog('push ' + nm + ' (' + Math.round(u8.length / 1024) + ' KiB)…');
        return ADB.pushFile(DP.shellStagingIncoming + '/' + nm, '0644', u8, null)
          .then(function () { done++; onLog('OK: pushed ' + nm + ' (' + done + '/' + names.length + ')'); });
      });
    });
    seq = seq.then(function () {
      onLog('push install.sh');
      return ADB.pushFile(DP.shellStagingInstallSh, '0755', textBytes(installSh), null);
    });
    seq = seq.then(function () {
      phase('running install.sh as root — often takes several minutes…');
      onLog('running install.sh as root…');
      // install.sh's last act is "DONE: install complete"; ADB.shell reports no
      // exit status, so that line — or a FAIL — is the verdict. Settle on it:
      // install.sh backgrounds the FlipMouse supervisor, and adbd never closes
      // a pty that a live daemon still holds, so waiting for the close hangs.
      var failed = null;
      var complete = false;
      return ADB.shell("su 0 sh -c 'sh " + DP.shellStagingInstallSh + "'", function (line) {
        if (line == null) return;
        if (/^FAIL:/.test(line)) failed = line;
        if (/^DONE: install complete$/.test(line)) complete = true;
        onLog(line);
      }, {
        settleOn: function (line) { return /^(DONE: install complete|FAIL:)/.test(line); },
        idleTimeoutMs: 15 * 60 * 1000
      }).then(function () {
        if (failed) throw new Error(failed);
        if (!complete) throw new Error('install.sh stopped before DONE — see the log above');
      });
    });
    return seq;
  },

  // verify.sh runs as root too; mirrors SUMMARY and rejects on the first FAIL.
  // Verify is reachable long after install, so cleanup may already have removed
  // the staging dir — recreate it before pushing.
  verify: function (verifySh, onLog) {
    if (!DP) {
      return Promise.reject(new Error('DEVICE_PATHS missing — run pipeline/wizard/gen-pipeline-js.sh'));
    }
    return PIPE.shellChecked('mkdir -p ' + DP.shellStaging, 'STAGING', onLog)
      .then(function () {
        return ADB.pushFile(DP.shellStagingVerifySh, '0755', textBytes(verifySh), null);
      })
      .then(function () {
        var failed = null;
        var summary = false;
        // Same pty contract as install: settle on the SUMMARY line (or the
        // first FAIL) instead of waiting for a close that may never come.
        return ADB.shell("su 0 sh -c 'sh " + DP.shellStagingVerifySh + "'", function (line) {
          if (line == null) return;
          if (/^FAIL:/.test(line)) failed = line;
          if (/^SUMMARY: /.test(line)) summary = true;
          onLog(line);
        }, {
          settleOn: function (line) { return /^(SUMMARY: |FAIL:)/.test(line); },
          idleTimeoutMs: 10 * 60 * 1000
        }).then(function () {
          if (failed) throw new Error(failed);
          if (!summary) throw new Error('verify.sh ended without a SUMMARY line');
        });
      });
  },

  // Clean incoming/ once install has fully succeeded (install.sh keeps it
  // for Retry until this runs). Root: the shell user cannot unlink under the
  // stage root (SELinux), and the staging area goes too.
  cleanup: function (onLog) {
    if (!DP) return Promise.resolve();
    return PIPE.shellChecked(
      "su 0 sh -c 'rm -rf " + DP.shellStaging + ' ' + DP.incomingDir + "/*'",
      'CLEAN', onLog
    ).then(function () { onLog('OK: cleaned incoming/ and staging'); });
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
        phase('running install.sh as root — often takes several minutes. Output appears when the script finishes.');
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

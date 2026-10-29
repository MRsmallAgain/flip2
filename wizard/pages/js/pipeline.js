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

var PIPE = {
  // files: map of catalog id -> Uint8Array (verified contents)
  // Returns a map remoteName -> Uint8Array ready to push.
  buildPushSet: function (files) {
    var installer = fflate.unzipSync(files['installer-full']);
    var want = [
      'payload/modules/flip2_nav_overlay-magisk.zip',
      'payload/modules/flip2_keypad_backspace-magisk.zip',
      'payload/modules/FlipMouse.zip',
      'payload/modules/flip2_launcher_overlay-magisk.zip'
    ];
    var out = {};
    var i, name;
    for (i = 0; i < want.length; i++) {
      if (!installer[want[i]]) throw new Error('installer zip is missing ' + want[i]);
      name = want[i].split('/').pop();
      out[name] = installer[want[i]];
    }
    var apks = ['payload/apks/launcher4.apk', 'payload/apks/nullkeyboard.apk'];
    for (i = 0; i < apks.length; i++) {
      if (!installer[apks[i]]) throw new Error('installer zip is missing ' + apks[i]);
      name = apks[i].split('/').pop();
      out[name] = installer[apks[i]];
    }

    // Tag Drawer: rebuild the module zip around the fresh F-Droid APK.
    var td = fflate.unzipSync(installer['payload/modules/flip2_pixel_tag_drawer-magisk.zip']);
    var tdEntry = 'system/app/PixelTagDrawer/PixelTagDrawer.apk';
    if (!td[tdEntry]) throw new Error('Tag Drawer zip is missing ' + tdEntry);
    td[tdEntry] = files['tagdrawer'];
    out['flip2_pixel_tag_drawer-magisk.zip'] = fflate.zipSync(td);

    // Default wallpaper, only if this installer zip carries one (older zips
    // predate the asset; install.sh treats its absence as a NOTE).
    var wpEntry = 'payload/wallpaper/flip2-wallpaper.png';
    if (installer[wpEntry]) {
      out['flip2-wallpaper.png'] = installer[wpEntry];
    }

    // Browser-downloaded files, renamed to the short names install.sh wants.
    out['forkgram.apk'] = files['forkgram'];
    out['intertune.apk'] = files['intertune'];
    out['bouncy.apk'] = files['bouncy'];
    out['materialfiles.apk'] = files['materialfiles'];
    out['ggml-tiny-q5_1.bin'] = files['whisper-tiny'];
    out['vosk-model-small-en-us-0.15.zip'] = files['vosk-en'];
    out['vosk-model-small-uk-v3-nano.zip'] = files['vosk-uk'];

    // sanity: the 14 names install.sh requires
    var need = ['flip2_nav_overlay-magisk.zip', 'flip2_keypad_backspace-magisk.zip',
      'FlipMouse.zip', 'flip2_pixel_tag_drawer-magisk.zip', 'flip2_launcher_overlay-magisk.zip',
      'launcher4.apk', 'nullkeyboard.apk', 'forkgram.apk', 'intertune.apk', 'bouncy.apk',
      'materialfiles.apk', 'ggml-tiny-q5_1.bin', 'vosk-model-small-en-us-0.15.zip',
      'vosk-model-small-uk-v3-nano.zip'];
    for (i = 0; i < need.length; i++) {
      if (!out[need[i]]) throw new Error('push set incomplete: ' + need[i]);
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
        onLog('push ' + nm + ' (' + Math.round(pushSet[nm].length / 1024) + ' KiB)…');
        return ADB.pushFile(INCOMING + nm, '0644', pushSet[nm], null)
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
  }
};

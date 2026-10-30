// Profile resolver for the Flip2 manager.
// Fetches ../profiles.json (wizard/profiles.json, byte-identical to
// pipeline/deploy/profiles.json). Managed extends base by concatenation.
// Secure stays visible and is not selectable.
//
// catalogIds() is the only list Apply and the download gate should use.
// neutron is never an Apply id.

var COMPONENT_META = {
  navoverlay: { label: 'Nav overlay', kind: 'module', moduleId: 'flip2_nav_overlay' },
  keypad: { label: 'Keypad backspace', kind: 'module', moduleId: 'flip2_keypad_backspace' },
  flipmouse: { label: 'FlipMouse', kind: 'module', moduleId: 'FlipMouse' },
  tagdrawer: { label: 'Tag Drawer', kind: 'module', moduleId: 'flip2_pixel_tag_drawer' },
  launcher_overlay: { label: 'Launcher overlay', kind: 'module', moduleId: 'flip2_launcher_overlay' },
  launcher4: {
    label: 'Launcher4',
    kind: 'apk',
    packageName: 'com.tim.flip2.launcher4',
    extraConfirm: 'Removing Launcher4 makes Home fall back to the stock launcher.'
  },
  ime: {
    label: 'Null Keyboard',
    kind: 'apk',
    packageName: 'com.tim.flip2.nullkeyboard',
    extraConfirm: 'Removing Null Keyboard makes the keyboard fall back to the stock input method.'
  },
  forkgram: { label: 'Forkgram', kind: 'apk', packageName: 'org.forkgram.classic' },
  materialfiles: { label: 'Material Files', kind: 'apk', packageName: 'me.zhanghai.android.files' },
  intertune: { label: 'Intertune', kind: 'apk', packageName: 'dev.skye.intertune' },
  bouncy: { label: 'Bouncy', kind: 'apk', packageName: 'com.dozingcatsoftware.bouncy' },
  home_keys: { label: 'Home keys', kind: 'settings' },
  display: { label: 'Display 321\u00d7428', kind: 'settings' },
  wallpaper: { label: 'Wallpaper', kind: 'settings' },
  whisper: { label: 'Whisper', kind: 'settings' },
  vosk: { label: 'Vosk', kind: 'settings' },
  headwind: { label: 'Headwind MDM', kind: 'apk', packageName: 'com.hmdm.launcher' }
};

// Component id -> catalog file ids. installer-full covers every component that
// lives in that zip (modules, launcher4, Null Keyboard, and the settings).
var CATALOG_FOR = {
  navoverlay: ['installer-full'],
  keypad: ['installer-full'],
  flipmouse: ['installer-full'],
  launcher_overlay: ['installer-full'],
  launcher4: ['installer-full'],
  ime: ['installer-full'],
  home_keys: ['installer-full'],
  display: ['installer-full'],
  wallpaper: ['installer-full'],
  tagdrawer: ['tagdrawer'],
  forkgram: ['forkgram'],
  materialfiles: ['materialfiles'],
  intertune: ['intertune'],
  bouncy: ['bouncy'],
  whisper: ['whisper-tiny'],
  vosk: ['vosk-en', 'vosk-uk'],
  headwind: ['headwind-launcher']
};

var PROFILES = {
  data: null,
  selectedId: 'base',
  // Confirmed from the pinned 15400 APK. The Companion handler ignores any
  // other component the page might send and uses this same string.
  deviceOwnerComponent: 'com.hmdm.launcher/.AdminReceiver',
  _listeners: [],

  onChange: function (fn) {
    this._listeners.push(fn);
  },

  load: function () {
    return fetch('../profiles.json').then(function (r) {
      if (!r.ok) throw new Error('profiles.json HTTP ' + r.status);
      return r.json();
    }).then(function (data) {
      if (!data || !data.profiles || !data.profiles.length) {
        throw new Error('profiles.json has no profiles');
      }
      PROFILES.data = data;
      var base = PROFILES.byId('base');
      if (!base || !base.components || !base.components.length) {
        throw new Error('profiles.json has no base components');
      }
      if (PROFILES.byId('base').enabled === false) {
        throw new Error('base profile is disabled');
      }
      PROFILES.selectedId = 'base';
      return data;
    });
  },

  list: function () {
    return (this.data && this.data.profiles) || [];
  },

  byId: function (id) {
    var list = this.list();
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) return list[i];
    }
    return null;
  },

  select: function (id) {
    var p = this.byId(id);
    if (!p) throw new Error('unknown profile: ' + id);
    if (p.enabled === false) throw new Error('profile is not selectable: ' + id);
    this.selectedId = id;
    for (var i = 0; i < this._listeners.length; i++) this._listeners[i](id);
    return id;
  },

  selected: function () {
    return this.byId(this.selectedId);
  },

  // Full component id list. Managed is base.components concatenated with adds.
  componentIds: function (id) {
    var p = this.byId(id || this.selectedId);
    if (!p) throw new Error('unknown profile: ' + (id || this.selectedId));
    if (p.components) return p.components.slice();
    if (p.extends) {
      var base = this.componentIds(p.extends);
      var adds = p.adds || [];
      for (var i = 0; i < adds.length; i++) {
        if (base.indexOf(adds[i]) < 0) base.push(adds[i]);
      }
      return base;
    }
    return [];
  },

  // Catalog ids the download gate and Apply must have verified.
  // neutron is intentionally absent.
  catalogIds: function (id) {
    var comps = this.componentIds(id);
    var out = [];
    for (var i = 0; i < comps.length; i++) {
      var mapped = CATALOG_FOR[comps[i]];
      if (!mapped) throw new Error('no catalog mapping for component: ' + comps[i]);
      for (var j = 0; j < mapped.length; j++) {
        if (mapped[j] === 'neutron') continue;
        if (out.indexOf(mapped[j]) < 0) out.push(mapped[j]);
      }
    }
    return out;
  },

  // One component id per line, trailing newline, for /data/local/flip2/profile.list.
  profileText: function (id) {
    return this.componentIds(id).join('\n') + '\n';
  },

  rows: function (id) {
    var comps = this.componentIds(id);
    var out = [];
    for (var i = 0; i < comps.length; i++) {
      var meta = COMPONENT_META[comps[i]];
      if (!meta) throw new Error('no row for component: ' + comps[i]);
      var row = { id: comps[i] };
      for (var k in meta) {
        if (Object.prototype.hasOwnProperty.call(meta, k)) row[k] = meta[k];
      }
      out.push(row);
    }
    return out;
  }
};

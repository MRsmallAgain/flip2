'use strict';

// VID/PID matching for the companion chooser.
// USB device ids are numbers. Serial port ids are optional strings; the
// installed Electron types do not fix the spelling. A numeric pair matches
// directly. A 0x prefix is hex. An all-digit pair is accepted when both ids
// match as decimal, or both match as hex — never one of each.
//
// CHOOSER_MS matches BOOTROM.boot's wait. requestPort blocks that wait, so a
// shorter cancel gives up while the page is still watching.

const CHOOSER_MS = 120000;

const ADB_IDS = [
  { vendorId: 0x1bbb, productId: 0x0167 },
  { vendorId: 0x1bbb, productId: 0x0c01 },
];

function inUsbId(n) {
  return Number.isInteger(n) && n >= 0 && n <= 0xffff;
}

function parseHex(text) {
  if (!/^(0x)?[0-9a-f]+$/i.test(text)) return null;
  const n = parseInt(text, 16);
  return inUsbId(n) ? n : null;
}

function parseDec(text) {
  if (!/^[0-9]+$/.test(text)) return null;
  const n = parseInt(text, 10);
  return inUsbId(n) ? n : null;
}

function idsMatch(device, vendorId, productId) {
  if (!device) return false;
  const v = device.vendorId;
  const p = device.productId;
  if (typeof v === 'number' && typeof p === 'number') {
    return v === vendorId && p === productId;
  }
  if (typeof v !== 'string' || typeof p !== 'string') return false;
  const vs = v.trim();
  const ps = p.trim();
  const vPref = /^0x/i.test(vs);
  const pPref = /^0x/i.test(ps);
  if (vPref || pPref) {
    if (!vPref || !pPref) return false;
    return parseHex(vs) === vendorId && parseHex(ps) === productId;
  }
  if (/[a-f]/i.test(vs) || /[a-f]/i.test(ps)) {
    return parseHex(vs) === vendorId && parseHex(ps) === productId;
  }
  if (parseDec(vs) === vendorId && parseDec(ps) === productId) return true;
  if (parseHex(vs) === vendorId && parseHex(ps) === productId) return true;
  return false;
}

function isPreloader(device) {
  return idsMatch(device, 0x0e8d, 0x2000);
}

function isFastbootUsb(device) {
  return idsMatch(device, 0x0e8d, 0x201c);
}

function isAdb(device) {
  return ADB_IDS.some(function (m) {
    return idsMatch(device, m.vendorId, m.productId);
  });
}

function idString(id) {
  if (typeof id === 'string' && id !== '') return id;
  if (typeof id === 'number' && Number.isInteger(id)) return String(id);
  return null;
}

function onlyPreloaderPortId(ports) {
  const hits = [];
  for (let i = 0; i < (ports || []).length; i++) {
    if (isPreloader(ports[i])) hits.push(ports[i]);
  }
  if (hits.length !== 1) return null;
  return idString(hits[0].portId);
}

// One allowed USB mode and one device. Fastboot is 0e8d:201c. Adb is a TCL
// id. Preloader 0e8d:2000 and bootrom 0e8d:0003 are never selected here.
// Both modes, or more than one device, returns null so the caller keeps waiting.
function soleUsbDeviceId(devices) {
  const hits = [];
  let mode = null;
  for (let i = 0; i < (devices || []).length; i++) {
    const d = devices[i];
    let next = null;
    if (isFastbootUsb(d)) next = 'fastboot';
    else if (isAdb(d)) next = 'adb';
    if (!next) continue;
    if (mode && mode !== next) return null;
    mode = next;
    hits.push(d);
  }
  if (hits.length !== 1) return null;
  return idString(hits[0].deviceId);
}

function itemKey(item) {
  if (!item) return '';
  const port = idString(item.portId);
  if (port) return 'p:' + port;
  const dev = idString(item.deviceId);
  if (dev) return 'd:' + dev;
  return '';
}

// Calls select exactly once. select(null) is a timeout or a closed window.
// An immediate choose() result does not wait and does not install listeners.
function holdChoice(ses, wc, items, addedEvent, removedEvent, choose, select, timeoutMs) {
  if (wc && typeof wc.isDestroyed === 'function' && wc.isDestroyed()) {
    select(null);
    return;
  }
  const ready = choose(items);
  if (ready !== null && ready !== undefined) {
    select(ready);
    return;
  }
  let settled = false;
  let timer = null;
  function cleanup() {
    clearTimeout(timer);
    ses.removeListener(addedEvent, onAdded);
    ses.removeListener(removedEvent, onRemoved);
    if (wc && typeof wc.removeListener === 'function' &&
        (typeof wc.isDestroyed !== 'function' || !wc.isDestroyed())) {
      wc.removeListener('destroyed', onDestroy);
    }
  }
  function finish(value) {
    if (settled) return;
    settled = true;
    cleanup();
    select(value);
  }
  function scoped(contents) {
    return !wc || contents === wc;
  }
  function onAdded(event, item, contents) {
    if (!scoped(contents)) return;
    const key = itemKey(item);
    if (!key) return;
    const idx = items.findIndex(function (cur) { return itemKey(cur) === key; });
    if (idx >= 0) items[idx] = item;
    else items.push(item);
    const next = choose(items);
    if (next !== null && next !== undefined) finish(next);
  }
  function onRemoved(event, item, contents) {
    if (!scoped(contents)) return;
    const key = itemKey(item);
    if (!key) return;
    const idx = items.findIndex(function (cur) { return itemKey(cur) === key; });
    if (idx >= 0) items.splice(idx, 1);
    const next = choose(items);
    if (next !== null && next !== undefined) finish(next);
  }
  function onDestroy() { finish(null); }
  const wait = timeoutMs === undefined ? CHOOSER_MS : timeoutMs;
  timer = setTimeout(function () { finish(null); }, wait);
  ses.on(addedEvent, onAdded);
  ses.on(removedEvent, onRemoved);
  if (wc && typeof wc.once === 'function') wc.once('destroyed', onDestroy);
}

function deliverUsb(callback, deviceId) {
  if (deviceId) callback(deviceId);
  else callback();
}

function deliverSerial(callback, portId) {
  callback(portId || '');
}

module.exports = {
  CHOOSER_MS: CHOOSER_MS,
  idsMatch: idsMatch,
  isPreloader: isPreloader,
  isFastbootUsb: isFastbootUsb,
  isAdb: isAdb,
  onlyPreloaderPortId: onlyPreloaderPortId,
  soleUsbDeviceId: soleUsbDeviceId,
  holdChoice: holdChoice,
  deliverUsb: deliverUsb,
  deliverSerial: deliverSerial,
};

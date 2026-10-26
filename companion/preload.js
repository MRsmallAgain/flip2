// Bridge exposed to the wizard pages as window.FLIP2_NATIVE.
// Absent when the same pages run in a plain browser — every caller must
// feature-check, so the pages keep working standalone.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('FLIP2_NATIVE', {
  udevStatus: function () { return ipcRenderer.invoke('udev-status'); },
  installUdev: function () { return ipcRenderer.invoke('install-udev'); },
});

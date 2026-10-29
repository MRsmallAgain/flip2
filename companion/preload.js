// Bridge exposed to the wizard pages as window.FLIP2_NATIVE.
// Absent when the same pages run in a plain browser — every caller must
// feature-check, so the pages keep working standalone.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('FLIP2_NATIVE', {
  udevStatus: function () { return ipcRenderer.invoke('udev-status'); },
  installUdev: function () { return ipcRenderer.invoke('install-udev'); },
  // Read-only USB mode of the phone, for the rooting step's status panel.
  phoneState: function () { return ipcRenderer.invoke('phone-state'); },
  // Files step: reuse copies already on this PC, or fetch them in-app.
  localFiles: function () { return ipcRenderer.invoke('local-files'); },
  readLocal: function (id, index) { return ipcRenderer.invoke('read-local', id, index); },
  downloadFile: function (id) { return ipcRenderer.invoke('download-file', id); },
  // Return to factory: adb work the page cannot do (no SYNC RECV in its client).
  factoryIdentity: function () { return ipcRenderer.invoke('factory-identity'); },
  factoryBackupBoot: function () { return ipcRenderer.invoke('factory-backup-boot'); },
  factoryState: function (fingerprint) { return ipcRenderer.invoke('factory-state', fingerprint); },
  factoryListBackups: function () { return ipcRenderer.invoke('factory-list-backups'); },
  factoryReadBackup: function (dest) { return ipcRenderer.invoke('factory-read-backup', dest); },
});

// Loaded by index.html before the other modules. Fetches the pinned catalog
// and exposes CATALOG { list, byId } once ready.

var CATALOG = { list: [], byId: {} };

function mergePinFields(entry, pin) {
  if (!pin) return entry;
  var out = {};
  var k;
  for (k in entry) {
    if (Object.prototype.hasOwnProperty.call(entry, k)) out[k] = entry[k];
  }
  if (pin.sha256 != null) out.sha256 = pin.sha256;
  if (pin.size != null) out.size = pin.size;
  if (pin.url != null && pin.url !== '') out.url = pin.url;
  if (pin.file != null && pin.file !== '') out.file = pin.file;
  return out;
}

function loadCatalog() {
  return Promise.all([
    fetch('../catalog.json').then(function (r) {
      if (!r.ok) throw new Error('catalog.json HTTP ' + r.status);
      return r.json();
    }),
    fetch('../pins.json').then(function (r) {
      if (!r.ok) return { files: [] };
      return r.json();
    }).catch(function () { return { files: [] }; }),
  ]).then(function (pair) {
    var cat = pair[0];
    var pins = pair[1];
    var pinById = {};
    (pins.files || []).forEach(function (p) { pinById[p.id] = p; });
    CATALOG.list = (cat.files || []).map(function (f) { return mergePinFields(f, pinById[f.id]); });
    CATALOG.byId = {};
    CATALOG.list.forEach(function (f) { CATALOG.byId[f.id] = f; });
    var stamp = document.getElementById('wizard-build');
    if (stamp) {
      var ver = (pins.version || cat.version || '').trim();
      stamp.textContent = ver ? 'Catalog ' + ver + ' · pins merge' : 'Catalog · pins merge';
      stamp.hidden = false;
      stamp.removeAttribute('aria-hidden');
    }
    return cat;
  });
}

// WebCrypto SHA-256 over a Blob/ArrayBuffer, hex output.
function sha256Hex(buf) {
  return crypto.subtle.digest('SHA-256', buf).then(function (digest) {
    var view = new Uint8Array(digest), out = '';
    for (var i = 0; i < view.length; i++) out += ('0' + view[i].toString(16)).slice(-2);
    return out;
  });
}

// Loaded by index.html before the other modules. Fetches the pinned catalog
// and exposes CATALOG { list, byId } once ready.

var CATALOG = { list: [], byId: {} };

function loadCatalog() {
  return fetch('../catalog.json')
    .then(function (r) { if (!r.ok) throw new Error('catalog.json HTTP ' + r.status); return r.json(); })
    .then(function (cat) {
      CATALOG.list = cat.files || [];
      CATALOG.byId = {};
      CATALOG.list.forEach(function (f) { CATALOG.byId[f.id] = f; });
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

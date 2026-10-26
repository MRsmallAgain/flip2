// ADB RSA key pair for the WebUSB client. Generated once, kept in
// localStorage as a JWK; the public side is encoded into the 524-byte
// ANDROID_PUBKEY blob (len | n0inv | n LE | rr LE | e) that adbd's
// android_pubkey_decode expects, base64 with a trailing NUL on the wire.

function b64uToBytes(s) {
  var t = s.replace(/-/g, '+').replace(/_/g, '/');
  while (t.length % 4) t += '=';
  var raw = atob(t), out = new Uint8Array(raw.length);
  for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

function bytesToBigIntBE(b) {
  var h = '0x';
  for (var i = 0; i < b.length; i++) h += ('0' + b[i].toString(16)).slice(-2);
  return BigInt(h);
}

// little-endian, zero-padded to len bytes
function bigIntToLE(x, len) {
  var out = new Uint8Array(len);
  for (var i = 0; i < len; i++) { out[i] = Number(x & 255n); x >>= 8n; }
  return out;
}

function modinv(a, m) {
  var r0 = m, r1 = ((a % m) + m) % m, s0 = 0n, s1 = 1n;
  while (r1) {
    var q = r0 / r1, tmp;
    tmp = r0 - q * r1; r0 = r1; r1 = tmp;
    tmp = s0 - q * s1; s0 = s1; s1 = tmp;
  }
  return ((s0 % m) + m) % m;
}

var ADBKEY = {
  ready: false, priv: null, pubB64: '',

  load: function () {
    var self = this;
    var alg = { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
                publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-1' };
    var saved = null;
    try { saved = localStorage.getItem('flip2_adb_key_jwk'); } catch (e) {}
    var got = function (jwk) {
      return crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-1' }, true, ['sign'])
        .then(function (k) { self.priv = k; self.pubB64 = self.encode(jwk); self.ready = true; });
    };
    if (saved) {
      try { return got(JSON.parse(saved)); } catch (e) { /* fall through to generate */ }
    }
    return crypto.subtle.generateKey(alg, true, ['sign']).then(function (pair) {
      return crypto.subtle.exportKey('jwk', pair.privateKey).then(function (jwk) {
        try { localStorage.setItem('flip2_adb_key_jwk', JSON.stringify(jwk)); } catch (e) {}
        return got(jwk);
      });
    });
  },

  // 524-byte blob per ANDROID_PUBKEY_ENCODE, then base64.
  encode: function (jwk) {
    var n = bytesToBigIntBE(b64uToBytes(jwk.n));
    var e = bytesToBigIntBE(b64uToBytes(jwk.e));
    var r32 = 1n << 32n;
    var n0inv = r32 - modinv(n % r32, r32);   // -1/n mod 2^32
    var rr = (1n << 4096n) % n;               // 2^4096 mod n, Montgomery rr
    var out = new Uint8Array(4 + 4 + 256 + 256 + 4);
    var dv = new DataView(out.buffer);
    dv.setUint32(0, 64, true);                // key_len in 32-bit words
    dv.setUint32(4, Number(n0inv), true);
    out.set(bigIntToLE(n, 256), 8);           // modulus, little-endian
    out.set(bigIntToLE(rr, 256), 8 + 256);
    dv.setUint32(8 + 512, Number(e), true);   // 65537
    var bin = '';
    for (var i = 0; i < out.length; i++) bin += String.fromCharCode(out[i]);
    return btoa(bin);
  },

  sign: function (token) {
    return crypto.subtle.sign({ name: 'RSASSA-PKCS1-v1_5' }, this.priv, token);
  }
};

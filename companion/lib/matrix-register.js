/**
 * Register a Matrix user via Synapse registration shared secret (Phase C).
 * No admin API — end-user accounts only. See docs/COMPANION-ONBOARDING.md.
 */
const crypto = require('crypto');

function randomPassword(len) {
  const chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.randomBytes(len);
  let out = '';
  for (let i = 0; i < len; i++) out += chars[bytes[i] % chars.length];
  return out;
}

function hsHostFromUrl(homeserverUrl) {
  const u = homeserverUrl.replace(/\/$/, '');
  try {
    return new URL(u).hostname;
  } catch (_e) {
    return u.replace(/^https?:\/\//, '').split('/')[0];
  }
}

/**
 * @param {typeof import('electron').net.fetch} fetchFn - net.fetch from Electron main
 * @param {{ homeserverUrl: string, username: string, password?: string, registrationSharedSecret: string }} opts
 */
async function registerMatrixUserSharedSecret(fetchFn, opts) {
  const hs = String(opts.homeserverUrl || '').replace(/\/$/, '');
  const username = String(opts.username || '').trim().toLowerCase();
  const secret = String(opts.registrationSharedSecret || '').trim();
  if (!hs || !username || !secret) {
    return { ok: false, error: 'homeserverUrl, username, and registrationSharedSecret required' };
  }
  if (!/^[a-z0-9._=\-\/]+$/.test(username)) {
    return { ok: false, error: 'Username: lowercase letters, digits, . _ = - / only' };
  }

  const password = opts.password && String(opts.password).length >= 8
    ? String(opts.password)
    : randomPassword(16);

  const nonceUrl = hs + '/_synapse/admin/v1/register';
  let res;
  try {
    res = await fetchFn(nonceUrl, { method: 'GET' });
  } catch (e) {
    return { ok: false, error: 'Cannot reach homeserver: ' + ((e && e.message) || String(e)) };
  }

  let body;
  try {
    body = await res.json();
  } catch (_e) {
    return { ok: false, error: 'Invalid JSON from registration endpoint (HTTP ' + res.status + ')' };
  }

  if (!res.ok || !body.nonce) {
    const err = body.error || body.errcode || ('HTTP ' + res.status);
    return { ok: false, error: String(err) };
  }

  const mac = crypto
    .createHmac('sha1', secret)
    .update(body.nonce + '\0' + username + '\0' + password + '\0notadmin')
    .digest('hex');

  const registerUrl = hs + '/_synapse/admin/v1/register';
  let res2;
  try {
    res2 = await fetchFn(registerUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        nonce: body.nonce,
        username,
        password,
        admin: false,
        mac,
      }),
    });
  } catch (e) {
    return { ok: false, error: 'Register POST failed: ' + ((e && e.message) || String(e)) };
  }

  let body2;
  try {
    body2 = await res2.json();
  } catch (_e) {
    return { ok: false, error: 'Invalid register response (HTTP ' + res2.status + ')' };
  }

  if (!res2.ok) {
    const err = body2.error || body2.errcode || ('HTTP ' + res2.status);
    if (/already/i.test(String(err))) {
      return { ok: false, error: 'Username taken — pick another localpart.' };
    }
    return { ok: false, error: String(err) };
  }

  const serverName = hsHostFromUrl(hs);
  const userId = body2.user_id || ('@' + username + ':' + serverName);

  return {
    ok: true,
    userId,
    username,
    password,
    homeserverUrl: hs,
  };
}

module.exports = {
  registerMatrixUserSharedSecret,
  randomPassword,
};

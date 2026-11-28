/**
 * Phase D: Matrix login + mautrix-whatsapp bot DM "login qr" + poll room for QR image.
 * User credentials only — no admin. Scan QR with smartphone WhatsApp.
 */
const { hsHostFromUrl } = require('./matrix-register');

function matrixBase(homeserverUrl) {
  return String(homeserverUrl || '').replace(/\/$/, '');
}

async function matrixLogin(fetchFn, homeserverUrl, userId, password) {
  const base = matrixBase(homeserverUrl);
  const localpart = userId.includes('@')
    ? userId.split(':')[0].slice(1)
    : userId;
  const res = await fetchFn(base + '/_matrix/client/v3/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      type: 'm.login.password',
      identifier: { type: 'm.id.user', user: localpart },
      password,
    }),
  });
  let body;
  try {
    body = await res.json();
  } catch (_e) {
    return { ok: false, error: 'Invalid login response' };
  }
  if (!res.ok) return { ok: false, error: body.error || body.errcode || 'Login failed' };
  return {
    ok: true,
    accessToken: body.access_token,
    userId: body.user_id,
    deviceId: body.device_id,
    homeserverUrl: base,
  };
}

async function findDmRoom(fetchFn, base, accessToken, botMxid) {
  const res = await fetchFn(base + '/_matrix/client/v3/joined_rooms', {
    headers: { Authorization: 'Bearer ' + accessToken },
  });
  if (!res.ok) return null;
  const data = await res.json();
  for (const roomId of data.joined_rooms || []) {
    const mres = await fetchFn(
      base + '/_matrix/client/v3/rooms/' + encodeURIComponent(roomId) + '/joined_members',
      { headers: { Authorization: 'Bearer ' + accessToken } }
    );
    if (!mres.ok) continue;
    const members = await mres.json();
    const joined = Object.keys(members.joined || {});
    if (joined.length === 2 && joined.includes(botMxid)) return roomId;
  }
  return null;
}

async function createDmRoom(fetchFn, base, accessToken, botMxid) {
  const res = await fetchFn(base + '/_matrix/client/v3/createRoom', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + accessToken,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      preset: 'trusted_private_chat',
      is_direct: true,
      invite: [botMxid],
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) return { ok: false, error: body.error || 'Could not open DM with bridge bot' };
  return { ok: true, roomId: body.room_id };
}

async function sendText(fetchFn, base, accessToken, roomId, bodyText) {
  const txn = 'flip2-' + Date.now();
  const res = await fetchFn(
    base +
      '/_matrix/client/v3/rooms/' +
      encodeURIComponent(roomId) +
      '/send/m.room.message/' +
      txn,
    {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer ' + accessToken,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ msgtype: 'm.text', body: bodyText }),
    }
  );
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    return { ok: false, error: err.error || 'Send failed' };
  }
  return { ok: true };
}

function sleep(ms) {
  return new Promise(function (r) { setTimeout(r, ms); });
}

async function pollQrImage(fetchFn, base, accessToken, roomId, timeoutMs) {
  const deadline = Date.now() + (timeoutMs || 120000);
  let from;
  while (Date.now() < deadline) {
    const url =
      base +
      '/_matrix/client/v3/rooms/' +
      encodeURIComponent(roomId) +
      '/messages?dir=b&limit=30' +
      (from ? '&from=' + encodeURIComponent(from) : '');
    const res = await fetchFn(url, {
      headers: { Authorization: 'Bearer ' + accessToken },
    });
    if (res.ok) {
      const data = await res.json();
      for (const ev of data.chunk || []) {
        if (ev.type !== 'm.room.message') continue;
        const c = ev.content || {};
        if (c.msgtype === 'm.image' && c.url) {
          return { mxc: c.url, mime: c.info && c.info.mimetype };
        }
      }
      from = data.end;
    }
    await sleep(2500);
  }
  return null;
}

async function fetchMxcAsDataUrl(fetchFn, base, accessToken, mxc) {
  const m = /^mxc:\/\/([^/]+)\/(.+)$/.exec(mxc);
  if (!m) return null;
  const mediaUrl =
    base +
    '/_matrix/client/v1/media/download/' +
    encodeURIComponent(m[1]) +
    '/' +
    encodeURIComponent(m[2]);
  const res = await fetchFn(mediaUrl, {
    headers: { Authorization: 'Bearer ' + accessToken },
  });
  if (!res.ok) return null;
  const buf = Buffer.from(await res.arrayBuffer());
  const ct = res.headers.get('content-type') || 'image/png';
  return 'data:' + ct + ';base64,' + buf.toString('base64');
}

function defaultWhatsappBot(homeserverUrl) {
  return '@whatsappbot:' + hsHostFromUrl(matrixBase(homeserverUrl));
}

async function whatsappQrProjector(fetchFn, opts) {
  const homeserverUrl = matrixBase(opts.homeserverUrl || 'https://bridge.flip2burn.online');
  const password = String(opts.password || '');
  let userId = String(opts.userId || '').trim();
  if (!userId.includes('@')) {
    userId = '@' + userId + ':' + hsHostFromUrl(homeserverUrl);
  }
  if (!password) return { ok: false, error: 'Matrix password required' };

  const botMxid = opts.botMxid || defaultWhatsappBot(homeserverUrl);
  const login = await matrixLogin(fetchFn, homeserverUrl, userId, password);
  if (!login.ok) return login;

  let roomId = await findDmRoom(fetchFn, login.homeserverUrl, login.accessToken, botMxid);
  if (!roomId) {
    const created = await createDmRoom(fetchFn, login.homeserverUrl, login.accessToken, botMxid);
    if (!created.ok) return created;
    roomId = created.roomId;
    await sleep(2000);
  }

  const sent = await sendText(fetchFn, login.homeserverUrl, login.accessToken, roomId, 'login qr');
  if (!sent.ok) return sent;

  const qr = await pollQrImage(
    fetchFn,
    login.homeserverUrl,
    login.accessToken,
    roomId,
    opts.timeoutMs
  );
  if (!qr) {
    return { ok: false, error: 'No QR from bridge yet — wait and retry, or check bot DM on FluffyChat.' };
  }

  const dataUrl = await fetchMxcAsDataUrl(
    fetchFn,
    login.homeserverUrl,
    login.accessToken,
    qr.mxc
  );
  if (!dataUrl) {
    return { ok: false, error: 'QR found but media download failed.', mxc: qr.mxc };
  }

  return {
    ok: true,
    qrDataUrl: dataUrl,
    botMxid,
    hint: 'Scan with WhatsApp on your smartphone (Linked devices).',
  };
}

module.exports = { whatsappQrProjector, defaultWhatsappBot, matrixLogin };

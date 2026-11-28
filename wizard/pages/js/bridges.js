// Unified messaging — FluffyChat + tier-2 bridges (bridge.flip2burn.online v1 default).
// Standalone in browser: copy buttons still work; phone actions need FLIP2_NATIVE.

var BRIDGES_CONFIG = {
  defaultHomeserver: 'https://bridge.flip2burn.online',
  defaultTier: 2,
  bots: [
    { id: 'whatsapp', label: 'WhatsApp', mxid: '@whatsappbot:bridge.flip2burn.online', cmd: 'login qr' },
    { id: 'signal', label: 'Signal', mxid: '@signalbot:bridge.flip2burn.online', cmd: 'link' },
    { id: 'gvoice', label: 'Google Voice', mxid: '@gvoicebot:bridge.flip2burn.online', cmd: 'login' }
  ]
};

function bridgesTierVisible() {
  if (typeof PROFILES === 'undefined' || !PROFILES.data) return false;
  return PROFILES.isComponentIncluded('fluffychat') || PROFILES.selectedId === 'messaging';
}

function bridgesCopyText(text, msgElId) {
  if (!text) return;
  var msgEl = typeof msgElId === 'string' ? $(msgElId) : msgElId;
  function done(ok) {
    if (msgEl && typeof setStatus === 'function') {
      setStatus(msgEl.id || 'bridges-msg', ok ? 'Copied.' : 'Copy failed — select text manually.', ok ? 'ok' : 'wait');
    }
  }
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(function () { done(true); }).catch(function () { fallbackCopy(text, done); });
  } else {
    fallbackCopy(text, done);
  }
}

function fallbackCopy(text, done) {
  var ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.left = '-9999px';
  document.body.appendChild(ta);
  ta.select();
  try {
    document.execCommand('copy');
    done(true);
  } catch (e) {
    done(false);
  }
  document.body.removeChild(ta);
}

function bridgesHomeserverUrl() {
  var inp = $('bridges-homeserver');
  if (inp && inp.value.trim()) return inp.value.trim().replace(/\/$/, '');
  return BRIDGES_CONFIG.defaultHomeserver;
}

function bridgesOpenFluffySignIn() {
  var N = window.FLIP2_NATIVE;
  if (!N || !N.wizardHostShell) {
    setStatus('bridges-msg', 'Phone actions need Flip 2 Companion.', 'bad');
    return;
  }
  var pkg = 'chat.fluffy.fluffychat';
  setStatus('bridges-msg', 'Opening FluffyChat on phone…', 'wait');
  var script =
    'am start -n ' + pkg + '/.MainActivity 2>/dev/null || ' +
    'monkey -p ' + pkg + ' -c android.intent.category.LAUNCHER 1 2>/dev/null; ' +
    'sleep 2; input keyevent 20; sleep 0.2; input keyevent 20; sleep 0.2; input keyevent 20; ' +
    'sleep 0.2; input keyevent 20; sleep 0.2; input keyevent 20';
  N.wizardHostShell({ cmd: script, timeoutMs: 25000 }).then(function (r) {
    if (!r || r.ok === false) {
      setStatus('bridges-msg', 'Could not open FluffyChat — install it first.', 'bad');
      return;
    }
    setStatus('bridges-msg',
      'FluffyChat opened. Homeserver: ' + bridgesHomeserverUrl() + '. OK → Sign in; enter credentials on phone.',
      'ok');
  }).catch(function (e) {
    setStatus('bridges-msg', cleanErr(e), 'bad');
  });
}

function bridgesOpenBotDm(mxid) {
  var N = window.FLIP2_NATIVE;
  if (!N || !N.wizardHostShell) {
    setStatus('bridges-msg', 'Companion required for phone open. MXID copied to clipboard if you use Copy.', 'wait');
    bridgesCopyText(mxid, 'bridges-msg');
    return;
  }
  setStatus('bridges-msg', 'Opening FluffyChat…', 'wait');
  var user = encodeURIComponent(mxid);
  var script =
    'am start -a android.intent.action.VIEW -d "matrix:u/' + user + '" 2>/dev/null || ' +
    'am start -n chat.fluffy.fluffychat/.MainActivity';
  N.wizardHostShell({ cmd: script, timeoutMs: 15000 }).then(function () {
    setStatus('bridges-msg', 'Start a chat with ' + mxid + ' if no room opened; send: ' +
      (BRIDGES_CONFIG.bots.find(function (b) { return b.mxid === mxid; }) || {}).cmd + '.', 'ok');
  }).catch(function (e) {
    setStatus('bridges-msg', cleanErr(e), 'bad');
  });
}

function bridgesSyncSecretUi() {
  var N = window.FLIP2_NATIVE;
  var manual = $('bridges-secret-manual');
  var wrap = $('bridges-secret-wrap');
  var hint = $('bridges-secret-hint');
  if (!hint) return;
  if (!N || !N.bridgeMatrixHasLocalSecret) {
    hint.textContent = 'Matrix registration needs Flip 2 Companion — paste registration secret manually if needed.';
    if (wrap) wrap.classList.remove('hidden');
    if (manual) manual.checked = true;
    return;
  }
  N.bridgeMatrixHasLocalSecret().then(function (r) {
    if (!r || !r.ok) return;
    if (r.hasSecret && manual && !manual.checked) {
      hint.textContent = 'Using registration secret from pipeline/bridge-kit/.env on this PC.';
      if (wrap) wrap.classList.add('hidden');
    } else if (manual && manual.checked) {
      hint.textContent = 'Paste SYNAPSE_REGISTRATION_SHARED_SECRET from VPS .env (not admin password).';
      if (wrap) wrap.classList.remove('hidden');
    } else {
      hint.textContent = 'No local .env — paste secret or run flip2 bridges rotate-creds.';
      if (wrap) wrap.classList.remove('hidden');
    }
  }).catch(function () { /* ignore */ });
}

function bridgesLastCreds() {
  return bridgesLastCreds._data || null;
}

function bridgesShowCreds(result) {
  var box = $('bridges-creds');
  if (!box || !result) return;
  var mxid = $('bridges-creds-mxid');
  var pass = $('bridges-creds-pass');
  if (mxid) mxid.textContent = result.userId || '';
  if (pass) pass.textContent = result.password || '';
  box.classList.remove('hidden');
  bridgesLastCreds._data = {
    userId: result.userId,
    password: result.password,
    homeserverUrl: result.homeserverUrl
  };
  var waPass = $('bridges-wa-password');
  if (waPass && result.password) waPass.value = result.password;
}

function bridgesWhatsappQrProjector() {
  var N = window.FLIP2_NATIVE;
  if (!N || !N.bridgeWhatsappQrProjector) {
    setStatus('bridges-msg', 'WhatsApp QR needs Flip 2 Companion.', 'bad');
    return;
  }
  var creds = bridgesLastCreds();
  var userId = creds && creds.userId ? creds.userId : '';
  var password = ($('bridges-wa-password') && $('bridges-wa-password').value) ||
    (creds && creds.password) || '';
  if (!userId) {
    var uname = ($('bridges-username') && $('bridges-username').value.trim()) || '';
    if (uname) {
      try {
        userId = '@' + uname + ':' + new URL(bridgesHomeserverUrl()).hostname;
      } catch (_e) {
        userId = '@' + uname + ':bridge.flip2burn.online';
      }
    }
  }
  if (!password) {
    setStatus('bridges-msg', 'Enter Matrix password (create account or type above).', 'bad');
    return;
  }
  if (!userId) {
    setStatus('bridges-msg', 'Create a Matrix account first or set username.', 'bad');
    return;
  }
  var btn = $('bridges-wa-qr');
  var display = $('bridges-wa-qr-display');
  var img = $('bridges-wa-qr-img');
  var hint = $('bridges-wa-qr-hint');
  if (btn) btn.disabled = true;
  if (display) display.classList.add('hidden');
  setStatus('bridges-msg', 'Logging in and asking bridge for QR (up to ~2 min)…', 'wait');
  N.bridgeWhatsappQrProjector({
    homeserverUrl: bridgesHomeserverUrl(),
    userId: userId,
    password: password,
    timeoutMs: 120000
  }).then(function (r) {
    if (btn) btn.disabled = false;
    if (!r || !r.ok) {
      setStatus('bridges-msg', (r && r.error) || 'WhatsApp QR failed.', 'bad');
      return;
    }
    if (img && r.qrDataUrl) img.src = r.qrDataUrl;
    if (hint) hint.textContent = r.hint || 'Scan with smartphone WhatsApp.';
    if (display) display.classList.remove('hidden');
    setStatus('bridges-msg', 'QR ready — scan with your phone WhatsApp.', 'ok');
  }).catch(function (e) {
    if (btn) btn.disabled = false;
    setStatus('bridges-msg', cleanErr(e), 'bad');
  });
}

function bridgesCreateMatrixAccount() {
  var N = window.FLIP2_NATIVE;
  if (!N || !N.bridgeMatrixRegisterUser) {
    setStatus('bridges-msg', 'Create account needs Flip 2 Companion.', 'bad');
    return;
  }
  var username = ($('bridges-username') && $('bridges-username').value.trim()) || '';
  if (!username) {
    setStatus('bridges-msg', 'Enter a username (localpart).', 'bad');
    return;
  }
  var payload = {
    homeserverUrl: bridgesHomeserverUrl(),
    username: username,
    password: ($('bridges-password') && $('bridges-password').value) || ''
  };
  if ($('bridges-secret-manual') && $('bridges-secret-manual').checked) {
    payload.registrationSharedSecret = ($('bridges-reg-secret') && $('bridges-reg-secret').value.trim()) || '';
  }
  var btn = $('bridges-create-account');
  if (btn) btn.disabled = true;
  setStatus('bridges-msg', 'Creating Matrix user…', 'wait');
  N.bridgeMatrixRegisterUser(payload).then(function (r) {
    if (btn) btn.disabled = false;
    if (!r || !r.ok) {
      setStatus('bridges-msg', (r && r.error) || 'Registration failed.', 'bad');
      return;
    }
    bridgesShowCreds(r);
    setStatus('bridges-msg', 'Account created — sign in on Flip with password above, then Open sign-in.', 'ok');
  }).catch(function (e) {
    if (btn) btn.disabled = false;
    setStatus('bridges-msg', cleanErr(e), 'bad');
  });
}

function syncBridgesPanel() {
  var panel = $('bridges-panel');
  if (!panel) return;
  panel.classList.toggle('hidden', !bridgesTierVisible());
  var hs = $('bridges-homeserver');
  if (hs && !hs.dataset.touched) hs.value = BRIDGES_CONFIG.defaultHomeserver;
  bridgesSyncSecretUi();
}

function initBridges() {
  if (!$('bridges-panel') || initBridges.bound) return;
  initBridges.bound = true;

  var hs = $('bridges-homeserver');
  if (hs) {
    hs.addEventListener('input', function () { hs.dataset.touched = '1'; });
  }
  $('bridges-copy-hs') && $('bridges-copy-hs').addEventListener('click', function () {
    bridgesCopyText(bridgesHomeserverUrl(), 'bridges-msg');
  });
  $('bridges-open-signin') && $('bridges-open-signin').addEventListener('click', bridgesOpenFluffySignIn);
  $('bridges-create-account') && $('bridges-create-account').addEventListener('click', bridgesCreateMatrixAccount);
  $('bridges-wa-qr') && $('bridges-wa-qr').addEventListener('click', bridgesWhatsappQrProjector);
  $('bridges-secret-manual') && $('bridges-secret-manual').addEventListener('change', bridgesSyncSecretUi);
  $('bridges-copy-pass') && $('bridges-copy-pass').addEventListener('click', function () {
    var el = $('bridges-creds-pass');
    if (el) bridgesCopyText(el.textContent, 'bridges-msg');
  });
  $('bridges-copy-creds') && $('bridges-copy-creds').addEventListener('click', function () {
    var mxid = $('bridges-creds-mxid');
    var pass = $('bridges-creds-pass');
    var hs = bridgesHomeserverUrl();
    if (!mxid || !pass) return;
    bridgesCopyText(
      'Homeserver: ' + hs + '\nUser: ' + mxid.textContent + '\nPassword: ' + pass.textContent,
      'bridges-msg'
    );
  });
  bridgesSyncSecretUi();

  var tier = $('bridges-tier');
  if (tier) {
    tier.value = String(BRIDGES_CONFIG.defaultTier);
    tier.addEventListener('change', function () {
      var note = $('bridges-tier-note');
      if (!note) return;
      if (tier.value === '1') {
        note.textContent = 'Tier 1: Beeper on-device where offered; Flip2 v1 usually needs tier 2.';
      } else if (tier.value === '3') {
        note.textContent = 'Tier 3: homelab bridge kit — set homeserver URL to your LAN/Tailscale host.';
      } else {
        note.textContent = 'Tier 2 (default): VPS at bridge.flip2burn.online — WA, Signal, GV via mautrix.';
      }
    });
    tier.dispatchEvent(new Event('change'));
  }

  var list = $('bridges-bot-list');
  if (list) {
    list.textContent = '';
    BRIDGES_CONFIG.bots.forEach(function (bot) {
      var row = document.createElement('div');
      row.className = 'bridges-bot-row';
      var title = document.createElement('strong');
      title.textContent = bot.label;
      row.appendChild(title);
      var code = document.createElement('code');
      code.className = 'bridges-mxid';
      code.textContent = ' ' + bot.mxid;
      row.appendChild(code);
      var hint = document.createElement('span');
      hint.className = 'note';
      hint.textContent = ' — in room, send: ' + bot.cmd;
      row.appendChild(hint);
      var actions = document.createElement('div');
      actions.className = 'bridges-bot-actions';
      var copyBtn = document.createElement('button');
      copyBtn.type = 'button';
      copyBtn.className = 'small ghost';
      copyBtn.textContent = 'Copy MXID';
      copyBtn.addEventListener('click', function () { bridgesCopyText(bot.mxid, 'bridges-msg'); });
      var dmBtn = document.createElement('button');
      dmBtn.type = 'button';
      dmBtn.className = 'small';
      dmBtn.textContent = 'Open on phone';
      dmBtn.addEventListener('click', function () { bridgesOpenBotDm(bot.mxid); });
      actions.appendChild(copyBtn);
      actions.appendChild(dmBtn);
      row.appendChild(actions);
      list.appendChild(row);
    });
  }

  if (typeof PROFILES !== 'undefined' && PROFILES.onChange) {
    PROFILES.onChange(syncBridgesPanel);
  }
  syncBridgesPanel();
}

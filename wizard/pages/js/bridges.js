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

function syncBridgesPanel() {
  var panel = $('bridges-panel');
  if (!panel) return;
  panel.classList.toggle('hidden', !bridgesTierVisible());
  var hs = $('bridges-homeserver');
  if (hs && !hs.dataset.touched) hs.value = BRIDGES_CONFIG.defaultHomeserver;
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

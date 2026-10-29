// Read-only probe for the return-to-factory page.
//
// Drives the real page through the three stages that never touch a partition:
// save a copy, check the copy, and ask the phone what it is afterwards. Those
// are the stages a host-level `fastboot flash` drill cannot exercise, because
// they live in the page. The write stages (flash, reboot, wipe) are deliberately
// unreachable from here — a probe must not be able to write just because it can
// click a button.
//
// Run with: electron . --factory-probe   (needs one phone on adb)

const fsp = require('fs').promises;
const path = require('path');

const sleep = (ms) => new Promise(function (r) { setTimeout(r, ms); });

async function runFactoryProbe(win, outDir) {
  await fsp.mkdir(outDir, { recursive: true });

  const js = (code) => win.webContents.executeJavaScript(code, true);

  const status = (id) => js('(function(){var e=document.getElementById("' + id + '");' +
    'return { text: e ? e.textContent : null, cls: e ? e.className : null };})()');

  const facts = (id) => js('(function(){var b=document.getElementById("' + id + '");' +
    'if(!b||b.classList.contains("hidden"))return [];' +
    'return Array.prototype.map.call(b.querySelectorAll(".now-row"),function(r){' +
    'return [r.children[0].textContent, r.children[1].textContent];});})()');

  const shot = async (name) => {
    const img = await win.webContents.capturePage();
    await fsp.writeFile(path.join(outDir, name + '.png'), img.toPNG());
  };

  // Wait for the status line to reach ok/bad instead of sleeping a fixed time:
  // dumping 24 MiB and re-reading it take different times on different phones.
  const settle = async (id, label, timeoutMs) => {
    const end = Date.now() + (timeoutMs || 60000);
    let last = null;
    while (Date.now() < end) {
      last = await status(id);
      if (last && /(^|\s)(ok|bad)(\s|$)/.test(last.cls || '')) return last;
      await sleep(250);
    }
    throw new Error(label + ' never settled, last state was ' + JSON.stringify(last));
  };

  const report = { startedAt: new Date().toISOString(), readings: {} };

  await js('document.getElementById("factory-link").click()');
  await sleep(200);
  report.readings.gateLockedBeforeTyping = await js('document.getElementById("factory-open").disabled');
  await shot('01-gate');

  // Type the word and tick the three boxes the way a person would, with real
  // input/change events, so this exercises the gate code rather than assigning
  // the disabled flag by hand.
  await js('(function(){var i=document.getElementById("factory-input");i.value="factory";' +
    'i.dispatchEvent(new Event("input",{bubbles:true}));' +
    '["fac-ack-copy","fac-ack-wipe","fac-ack-state"].forEach(function(id){' +
    'var c=document.getElementById(id);c.checked=true;' +
    'c.dispatchEvent(new Event("change",{bubbles:true}));});return true;})()');
  await sleep(200);
  await shot('02-gate-open');
  if (await js('document.getElementById("factory-open").disabled')) {
    throw new Error('the gate stayed locked after the word and all three acknowledgements');
  }

  await js('document.getElementById("factory-open").click()');
  await sleep(200);
  await shot('03-step1');
  report.readings.stageShown = await js('(function(){var on=[].filter.call(' +
    'document.querySelectorAll("[id^=fac-stage-]"),function(e){' +
    'return !e.classList.contains("hidden");});return on.map(function(e){return e.id;});})()');

  // 1 - save a copy off the phone.
  await js('document.getElementById("fac-backup").click()');
  const saved = await settle('fac-backup-msg', 'saving a copy', 240000);
  await shot('04-step1-saved');
  report.readings.save = { text: saved.text, cls: saved.cls };
  report.readings.saveFacts = await facts('fac-backup-facts');
  if (/bad/.test(saved.cls || '')) throw new Error('saving the copy failed: ' + saved.text);

  // A successful dump should also refresh the list of copies on this computer.
  report.readings.listedCopies = await js('document.getElementById("fac-copies").options.length');
  report.readings.copiesWrapVisible = await js(
    '!document.getElementById("fac-copies-wrap").classList.contains("hidden")');

  // 2 - check it, which re-reads and re-hashes the file off disk.
  if (await js('document.getElementById("fac-backup-next").disabled')) {
    throw new Error('step 1 did not enable Continue after a good copy was saved');
  }
  await js('document.getElementById("fac-backup-next").click()');
  await sleep(300);
  await shot('05-step2-chosen');
  report.readings.chosenFacts = await facts('fac-picked');

  await js('document.getElementById("fac-verify").click()');
  const checked = await settle('fac-verify-msg', 'checking the copy', 120000);
  await shot('06-step2-checked');
  report.readings.check = { text: checked.text, cls: checked.cls };
  report.readings.checkLog = await js('document.getElementById("fac-verify-log").textContent');
  if (/bad/.test(checked.cls || '')) throw new Error('checking the copy failed: ' + checked.text);
  report.readings.step3Ready = await js('!document.getElementById("fac-verify-next").disabled');

  // 6 - ask the phone what it is, compared against the copy just chosen.
  // Jumped to directly, because flash, reboot and wipe are not run by a probe.
  await js('facStage("done")');
  await sleep(200);
  await shot('07-step6');

  await js('document.getElementById("fac-check").click()');
  const after = await settle('fac-check-msg', 'checking the phone', 180000);
  await shot('08-step6-checked');
  report.readings.state = { text: after.text, cls: after.cls };
  report.readings.stateFacts = await facts('fac-facts');

  report.shots = (await fsp.readdir(outDir)).sort();
  report.finishedAt = new Date().toISOString();
  return report;
}

module.exports = { runFactoryProbe };

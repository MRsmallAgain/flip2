# STT / Null Keyboard handoff (2026-11-18)

**Shipped commit:** `d9ed957` — Null Keyboard **2.7.15-stt** (`versionCode` 57) + FlipMouse star IME handoff.

**User verdict (post-fix):** Dictation quality and flow are good in **regular (passive) FlipMouse** mode. One regression remains around `*` falling through to **literal star / T9/case** after certain activation / mode fiddling.

---

## What landed in this commit

### Null Keyboard (`com.tim.flip2.nullkeyboard`)

| Area | Change |
|------|--------|
| Engine | **Sherpa offline NeMo** for **both** `en` and `uk` — batch decode on `*` **release** (zipformer streaming experiment reverted). |
| PTT startup | `mPttLock`; **synchronous** `beginCapture` when offline model warm; `mPendingBeginCapture` removed on stop; session guards. |
| Commit path | `mCommitBg` so next PTT is not blocked behind decode; **release commits when `isListening()`** (not only after `HOLD_MS` 380 ms). |
| IME `*` | Ignore duplicate DOWN while `mStarKeyDown`; `mStarSttSession` for UP after state cleared. |
| Docs in `ime.sh` | PTT = hold `*`, release to commit; `#` = lang while listening. |

### FlipMouse

| Area | Change |
|------|--------|
| Cursor mode | `*` **ungrab + inject** to IME; does **not** call `mouse_deactivate()`; `#` passes through during handoff. |
| Deploy | `ondevice-install.sh`: kill `mouse`, wait, atomic `mouse.new` → `mouse` (fixes “Text file busy”). |

### Deploy / verify

```bash
flip2 ime hide-bar          # build if src newer than APK
flip2 flipmouse install       # if cursor + * path touched
adb logcat -s Flip2STT Flip2IME
```

**Self-test (adb, Forkgram):** `adb input keyevent 17` ×2 — expect `listening session=N` then `onFinal session=N source=OFFLINE`. First PTT after IME cold start may wait ~10–15 s for offline recognizer load (`offline_warm=false`).

---

## Outstanding issues (priority order)

### P1 — `*` sometimes prints `*` / cycles case (regular mode)

**Reporter:** User, after “messing around with activation” in **passive FlipMouse** (no cursor).

**Symptom:** `*` stops opening PTT and behaves like a **quick tap** (`applyStarPoundTap` → T9 / case), or commits literal `*` in numeric mode.

**Likely code paths**

- `NullKeyboardService.handleStarPound`: `startListening()` returns false → no `mStarSttSession`; UP takes non-STT branch.
- UP with `deliverFinal=false` when neither `isListening()` nor `sttSession` → `applyStarPoundTap`.
- `mStarKeyDown` / `mStarSttSession` desync if DOWN swallowed or UP without matching DOWN.
- Mode / activation changes: FlipMouse **passive** should deliver native matrix `*`; if user toggled cursor recently, confirm `star_ime_handoff` and grab state in `/cache/FlipMouse.log`.

**Repro protocol**

1. Note FlipMouse state: `adb shell pgrep -a mouse`; tail `/cache/FlipMouse.log`.
2. Repro steps user used (soft-key hold to enter/exit cursor, etc.).
3. One bad press: `adb logcat -s Flip2STT Flip2IME` — look for `forwardKey code=17`, `ptt start`, `startListening` failure / `ic=null`, `ptt start ignored`.
4. Compare good vs bad: is `mStt.startListening()` false (permission, model, libs)?

**Hardening ideas (not implemented)**

- Log on `startListening()` false and on UP when `sttSession==false` but user held >200 ms.
- Reset star state on `onWindowShown` / FlipMouse passive transition.
- Optional: debounce or require minimum hold before T9/case on `*` UP if mic permission OK and models present.

---

### P2 — NeMo “English” label vs Cyrillic-heavy output

**History:** EN and UK dirs both use the **same multilingual NeMo tarball** (`fetch-sherpa-models.sh` copies `uk` → `en`). STT quality was preferred over zipformer EN (clipping).

**Open:** No reliable `language` hint found for Sherpa NeMo transducer path; EN pref may still decode with multilingual tokenizer bias (Cyrillic glyphs).

**Directions (research)**

- Sherpa NeMo C++ / Java API for locale or blank/prompt.
- Separate **English-only** offline model if acceptable size on device.
- User workaround: `#` → UK vs EN may not fix script; document that both share NeMo pack today.

---

### P3 — Documentation drift

| Doc | Problem |
|-----|---------|
| `docs/SHERPA-STT.md` | Still describes **EN zipformer streaming** + old UX (`*` stops while listening). |
| `docs/LESSONS-LEARNED.md` | Sherpa section may be partially stale. |
| Plan file | Zipformer clipping plan (`plan-sess_97561a88…`) **obsolete** for engine choice; keep only if revisiting streaming partials. |

**Action:** Update `SHERPA-STT.md` to match NeMo offline both langs, release-to-commit, FGS, click-mute notes, version 2.7.15+ behavior.

---

### P4 — Cursor mode + IME (lower urgency if passive is daily driver)

- FlipMouse inject + native delivery after ungrab: duplicate `*` DOWN was mitigated (handoff flag + IME `mStarKeyDown`).
- WebUSB / wizard debt unchanged ([[project-flip2-wizard-debt]]).
- Confirm regrab after `*` UP does not eat the next physical `*` in passive.

---

### P5 — CI / release (when promoting)

- Uncommitted work was only this STT slice; run `flip2 ci` / gates before release tag.
- Catalog pins: NeMo tarball id unchanged; APK version **57** not necessarily in release manifest until tagged.

---

## Key files

```
pipeline/ime/null-keyboard/src/.../SherpaSttHelper.java   # PTT, offline decode, mPttLock
pipeline/ime/null-keyboard/src/.../NullKeyboardService.java # handleStarPound, forwardKey, HOLD_MS
pipeline/ime/null-keyboard/models/fetch-sherpa-models.sh   # NeMo uk → en copy
pipeline/flipmouse/main.c                                  # star_ime_handoff
pipeline/ime/ime.sh
```

---

## Session timeline (for the next agent)

1. User lost `*` → Listening (`beginCapture abort startup`); fixed sync warm path + commit when Listening.
2. Duplicate `ptt start` — locks + duplicate DOWN guards.
3. User: **everything awesome** except intermittent `*` → star character after activation experiments.
4. Commit `d9ed957`; this handoff.

---

## Memory / related

- [[project-flip2-sherpa-stt]] — preroll, FGS, deploy path.
- User rule: **do not push** unless asked; commit was requested here only.

#!/usr/bin/env bash
# User APK cannot bind NotificationListener (STATUS_BAR_SERVICE) — skip priv crash paths.
set -euo pipefail
FLIP2_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$FLIP2_ROOT/lib/bootstrap.sh"

WORK="${1:?Usage: skip-priv-features.sh <decoded-dir>}"
LAUNCHER="$WORK/smali/com/android/launcher3/Launcher.smali"
[[ -f "$LAUNCHER" ]] || { echo "Missing $LAUNCHER" >&2; exit 1; }

python3 - "$LAUNCHER" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
changed = []

block = """    .line 626
    new-instance p1, Landroid/content/Intent;

    const-class v0, Lcom/android/launcher3/notification/NotificationListener;

    invoke-direct {p1, p0, v0}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V

    const-string v0, "type"

    const-string v1, "local_binding"

    .line 627
    invoke-virtual {p1, v0, v1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    const-string v0, "Launcher"

    const-string v1, "bindService"

    .line 628
    invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    .line 629
    iget-object v0, p0, Lcom/android/launcher3/Launcher;->mNotificationListenerConnection:Landroid/content/ServiceConnection;

    invoke-virtual {p0, p1, v0, v4}, Landroid/app/Activity;->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z

"""
if block in t:
    t = t.replace(block, "    # flip2 launcher4: skip NotificationListener (priv STATUS_BAR_SERVICE)\n\n", 1)
    changed.append("NotificationListener bindService removed")

sq_anchor = """.method private showQuickSettings(Z)Z
    .locals 3

    .line 3748
    iget-object v0, p0, Lcom/android/launcher3/Launcher;->mState:Lcom/android/launcher3/Launcher$State;
"""
sq_repl = """.method private showQuickSettings(Z)Z
    .locals 1

    # flip2 launcher4: QuickSettings disabled (user APK)
    const/4 v0, 0x0

    return v0

    .line 3748
    iget-object v0, p0, Lcom/android/launcher3/Launcher;->mState:Lcom/android/launcher3/Launcher$State;
"""
if sq_anchor in t and "QuickSettings disabled (user APK)" not in t:
    t = t.replace(sq_anchor, sq_repl, 1)
    changed.append("showQuickSettings disabled")

rk_old = """    :cond_2
    invoke-direct {v0, v6}, Lcom/android/launcher3/Launcher;->showQuickSettings(Z)Z

    .line 1584
    iget-object v1, v0, Lcom/android/launcher3/Launcher;->mAudioManager:Landroid/media/AudioManager;

    invoke-virtual {v1, v6}, Landroid/media/AudioManager;->playSoundEffect(I)V

    return v5

    .line 1589
    :cond_3"""
rk_new = """    :cond_2
    # flip2 launcher4: Shortcuts -> keyshortcut_rightkey (flip2 home-keys)
    invoke-virtual {v0}, Landroid/app/Activity;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v1

    const-string v2, "keyshortcut_rightkey"

    invoke-static {v1, v2}, Landroid/provider/Settings$Global;->getString(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/String;

    move-result-object v1

    iget-object v2, v0, Lcom/android/launcher3/Launcher;->mAudioManager:Landroid/media/AudioManager;

    invoke-virtual {v2, v6}, Landroid/media/AudioManager;->playSoundEffect(I)V

    invoke-direct {v0, v1}, Lcom/android/launcher3/Launcher;->startShortcutsApp(Ljava/lang/String;)V

    return v5

    .line 1589
    :cond_3"""
rk_bar = """    :cond_2
    # flip2 launcher4: Shortcuts bar -> keyshortcut_shortcutsbar (flip2 home-keys shortcuts_bar)
    invoke-virtual {v0}, Landroid/app/Activity;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v1

    const-string v2, "keyshortcut_shortcutsbar"

    invoke-static {v1, v2}, Landroid/provider/Settings$Global;->getString(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/String;

    move-result-object v1

    iget-object v2, v0, Lcom/android/launcher3/Launcher;->mAudioManager:Landroid/media/AudioManager;

    invoke-virtual {v2, v6}, Landroid/media/AudioManager;->playSoundEffect(I)V

    invoke-direct {v0, v1}, Lcom/android/launcher3/Launcher;->startShortcutsApp(Ljava/lang/String;)V

    return v5

    .line 1589
    :cond_3"""
rk_noop = """    :cond_2
    # flip2 launcher4: skip Shortcuts/QuickSettings soft key

    return v5

    .line 1589
    :cond_3"""
bar_marker = "flip2 launcher4: Shortcuts bar -> keyshortcut_shortcutsbar"
noop_marker = "flip2 launcher4: skip Shortcuts/QuickSettings soft key"
right_marker = "flip2 launcher4: Shortcuts -> keyshortcut_rightkey"
if bar_marker not in t:
    if noop_marker in t and rk_noop in t:
        t = t.replace(rk_noop, rk_bar, 1)
        changed.append("Shortcuts bar -> keyshortcut_shortcutsbar")
    elif right_marker in t and rk_new in t:
        t = t.replace(rk_new, rk_bar, 1)
        changed.append("Shortcuts bar -> keyshortcut_shortcutsbar (was rightkey)")
    elif rk_old in t:
        t = t.replace(rk_old, rk_bar, 1)
        changed.append("Shortcuts bar -> keyshortcut_shortcutsbar")

qs_old = """    .line 5184
    :cond_1
    new-instance p1, Landroid/content/Intent;

    const-class v0, Lcom/android/launcher3/quicksettings/QuickShortActivity;

    invoke-direct {p1, p0, v0}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V

    const/16 v0, 0x808

    .line 5185
    invoke-virtual {p0, p1, v0}, Landroid/app/Activity;->startActivityForResult(Landroid/content/Intent;I)V

    :goto_0
    return-void"""
qs_new = """    .line 5184
    :cond_1
    # flip2 launcher4: skip QuickShortActivity

    :goto_0
    return-void"""
if qs_old in t and "skip QuickShortActivity" not in t:
    t = t.replace(qs_old, qs_new, 1)
    changed.append("QuickShortActivity launch disabled")

fn_old = """    invoke-static {v0, v1}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    .line 4436
    iget-object v0, p0, Lcom/android/launcher3/Launcher;->mPopupDataProvider:Lcom/android/launcher3/popup/PopupDataProvider;

    invoke-static {v0}, Lcom/android/launcher3/notification/NotificationListener;->setNotificationsChangedListener(Lcom/android/launcher3/notification/NotificationListener$NotificationsChangedListener;)V

    const/4 v0, 0x0

    .line 4437"""
fn_new = """    invoke-static {v0, v1}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    .line 4436
    # flip2 launcher4: skip setNotificationsChangedListener

    const/4 v0, 0x0

    .line 4437"""
if fn_old in t and "skip setNotificationsChangedListener" not in t:
    t = t.replace(fn_old, fn_new, 1)
    changed.append("setNotificationsChangedListener skipped")

p.write_text(t)
if changed:
    for c in changed:
        print(f"skip-priv-features: {c}")
else:
    print("skip-priv-features: already patched or anchors missing")
PY

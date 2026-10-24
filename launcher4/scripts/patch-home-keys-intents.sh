#!/usr/bin/env bash
# home-keys: special intents for TCL Settings (MAIN/LAUNCHER → SIM/wrong screen).
set -euo pipefail
WORK="${1:?Usage: patch-home-keys-intents.sh <decoded-dir>}"
LAUNCHER="$WORK/smali/com/android/launcher3/Launcher.smali"
[[ -f "$LAUNCHER" ]] || { echo "Missing $LAUNCHER" >&2; exit 1; }

python3 - "$LAUNCHER" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

WIFI_MARKER = "flip2 launcher4: WifiSettings -> WIFI_SETTINGS"

if WIFI_MARKER in t:
    print("patch-home-keys-intents: already applied (wifi/bt/network actions)")
    raise SystemExit(0)

upgrade_anchor = """    aget-object p1, p1, v2

    const-string v2, "NetworkDashboardActivity"

    invoke-virtual {p1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z"""

upgrade_insert = """    aget-object p1, p1, v2

    const-string v2, "WifiSettings"

    invoke-virtual {p1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v2

    if-eqz v2, :flip2_wifi_settings_intent

    const-string v2, "ConnectedDeviceDashboardActivity"

    invoke-virtual {p1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v2

    if-eqz v2, :flip2_bluetooth_settings_intent

    const-string v2, "NetworkDashboardActivity"

    invoke-virtual {p1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z"""

wifi_bt_blocks = """
    :flip2_wifi_settings_intent
    # flip2 launcher4: WifiSettings -> WIFI_SETTINGS
    new-instance v1, Landroid/content/ComponentName;

    invoke-direct {v1, v0, p1}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V

    new-instance p1, Landroid/content/Intent;

    const-string v0, "android.settings.WIFI_SETTINGS"

    invoke-direct {p1, v0}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    invoke-virtual {p1, v1}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;

    move-result-object p1

    const/high16 v0, 0x10000000

    invoke-virtual {p1, v0}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    move-result-object p1

    return-object p1

    :flip2_bluetooth_settings_intent
    # flip2 launcher4: ConnectedDevice -> BLUETOOTH_SETTINGS
    new-instance v1, Landroid/content/ComponentName;

    invoke-direct {v1, v0, p1}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V

    new-instance p1, Landroid/content/Intent;

    const-string v0, "android.settings.BLUETOOTH_SETTINGS"

    invoke-direct {p1, v0}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    invoke-virtual {p1, v1}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;

    move-result-object p1

    const/high16 v0, 0x10000000

    invoke-virtual {p1, v0}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    move-result-object p1

    return-object p1

    :flip2_wireless_settings_intent"""

if upgrade_anchor in t:
    t = t.replace(upgrade_anchor, upgrade_insert, 1)
    anchor = "\n    :flip2_wireless_settings_intent"
    if anchor in t and ":flip2_wifi_settings_intent" not in t:
        t = t.replace(anchor, wifi_bt_blocks, 1)
    p.write_text(t)
    print("patch-home-keys-intents: added WifiSettings + Bluetooth settings actions")
    raise SystemExit(0)

old = """    .line 1834
    aget-object v0, p1, v0

    .line 1835
    aget-object p1, p1, v2

    .line 1836
    new-instance v1, Landroid/content/ComponentName;

    invoke-direct {v1, v0, p1}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V

    .line 1837
    new-instance p1, Landroid/content/Intent;

    const-string v0, "android.intent.action.MAIN"

    invoke-direct {p1, v0}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    const-string v0, "android.intent.category.LAUNCHER"

    .line 1838
    invoke-virtual {p1, v0}, Landroid/content/Intent;->addCategory(Ljava/lang/String;)Landroid/content/Intent;

    move-result-object p1

    .line 1839
    invoke-virtual {p1, v1}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;

    move-result-object p1

    const/high16 v0, 0x10200000

    .line 1840
    invoke-virtual {p1, v0}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    move-result-object p1

    return-object p1"""

new = old.replace(
    "    .line 1836\n    new-instance v1",
    """    const-string v2, "WifiSettings"

    invoke-virtual {p1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v2

    if-eqz v2, :flip2_wifi_settings_intent

    const-string v2, "ConnectedDeviceDashboardActivity"

    invoke-virtual {p1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v2

    if-eqz v2, :flip2_bluetooth_settings_intent

    const-string v2, "NetworkDashboardActivity"

    invoke-virtual {p1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v2

    if-eqz v2, :flip2_wireless_settings_intent

    .line 1836
    new-instance v1""",
    1,
)

# Full new block for fresh decode - append special handlers before :cond_1
if old not in t:
    print("patch-home-keys-intents: pattern not found (launcher version?)", file=sys.stderr)
    raise SystemExit(1)

# For fresh install use complete replacement from prior script
full_new = """    .line 1834
    aget-object v0, p1, v0

    .line 1835
    aget-object p1, p1, v2

    const-string v2, "WifiSettings"

    invoke-virtual {p1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v2

    if-eqz v2, :flip2_wifi_settings_intent

    const-string v2, "ConnectedDeviceDashboardActivity"

    invoke-virtual {p1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v2

    if-eqz v2, :flip2_bluetooth_settings_intent

    const-string v2, "NetworkDashboardActivity"

    invoke-virtual {p1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v2

    if-eqz v2, :flip2_wireless_settings_intent

    .line 1836
    new-instance v1, Landroid/content/ComponentName;

    invoke-direct {v1, v0, p1}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V

    .line 1837
    new-instance p1, Landroid/content/Intent;

    const-string v0, "android.intent.action.MAIN"

    invoke-direct {p1, v0}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    const-string v0, "android.intent.category.LAUNCHER"

    .line 1838
    invoke-virtual {p1, v0}, Landroid/content/Intent;->addCategory(Ljava/lang/String;)Landroid/content/Intent;

    move-result-object p1

    .line 1839
    invoke-virtual {p1, v1}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;

    move-result-object p1

    const/high16 v0, 0x10200000

    .line 1840
    invoke-virtual {p1, v0}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    move-result-object p1

    return-object p1

    :flip2_wifi_settings_intent
    # flip2 launcher4: WifiSettings -> WIFI_SETTINGS
    new-instance v1, Landroid/content/ComponentName;

    invoke-direct {v1, v0, p1}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V

    new-instance p1, Landroid/content/Intent;

    const-string v0, "android.settings.WIFI_SETTINGS"

    invoke-direct {p1, v0}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    invoke-virtual {p1, v1}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;

    move-result-object p1

    const/high16 v0, 0x10000000

    invoke-virtual {p1, v0}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    move-result-object p1

    return-object p1

    :flip2_bluetooth_settings_intent
    # flip2 launcher4: ConnectedDevice -> BLUETOOTH_SETTINGS
    new-instance v1, Landroid/content/ComponentName;

    invoke-direct {v1, v0, p1}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V

    new-instance p1, Landroid/content/Intent;

    const-string v0, "android.settings.BLUETOOTH_SETTINGS"

    invoke-direct {p1, v0}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    invoke-virtual {p1, v1}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;

    move-result-object p1

    const/high16 v0, 0x10000000

    invoke-virtual {p1, v0}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    move-result-object p1

    return-object p1

    :flip2_wireless_settings_intent
    # flip2 launcher4: NetworkDashboard -> WIRELESS_SETTINGS + TctNetworkDashboardFragment
    new-instance v1, Landroid/content/ComponentName;

    invoke-direct {v1, v0, p1}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V

    new-instance p1, Landroid/content/Intent;

    const-string v0, "android.settings.WIRELESS_SETTINGS"

    invoke-direct {p1, v0}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    invoke-virtual {p1, v1}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;

    move-result-object p1

    const-string v0, ":settings:show_fragment"

    const-string v1, "com.android.settings.network.TctNetworkDashboardFragment"

    invoke-virtual {p1, v0, v1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    move-result-object p1

    const/high16 v0, 0x10000000

    invoke-virtual {p1, v0}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    move-result-object p1

    return-object p1"""

p.write_text(t.replace(old, full_new, 1))
print("patch-home-keys-intents: wifi/bt/network settings actions")
PY

#!/usr/bin/env python3
"""Patch mautrix config.yaml homeserver URL, domain, and admin permissions."""
import os
import pathlib
import re

p = pathlib.Path("/data/config.yaml")
t = p.read_text()
addr = os.environ["MAUTRIX_HOMESERVER_URL"]
domain = os.environ["SYNAPSE_SERVER_NAME"]
admin = os.environ.get("MAUTRIX_ADMIN_MXID", f"@flip2admin:{domain}")

t = re.sub(r"^    address:.*", f"    address: {addr}", t, count=1, flags=re.M)
t = re.sub(r"^    domain:.*", f"    domain: {domain}", t, count=1, flags=re.M)

perm_block = (
    "    permissions:\n"
    f'        "{admin}": admin\n'
    '        "*": relay\n'
)
t = re.sub(
    r"^    permissions:\n(?:        .+\n)+",
    perm_block,
    t,
    count=1,
    flags=re.M,
)

# v1: SQLite per bridge volume (no separate Postgres DB per bridge)
db_block = (
    "database:\n"
    "    type: sqlite3-fk-wal\n"
    '    uri: file:/data/bridge.db?_txlock=immediate\n'
    "    max_open_conns: 5\n"
    "    max_idle_conns: 1\n"
)
t = re.sub(r"^database:\n(?:    .+\n)+", db_block, t, count=1, flags=re.M)

# Listen on all interfaces so Synapse (another container) can reach the appservice HTTP server
t = re.sub(r"^    hostname:.*", "    hostname: 0.0.0.0", t, count=1, flags=re.M)

p.write_text(t)
print("patched", p)

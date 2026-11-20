#!/usr/bin/env python3
"""Patch /data/homeserver.yaml in Synapse data volume (Postgres, public URL, registration off)."""
import os
import pathlib
import re

p = pathlib.Path("/data/homeserver.yaml")
if not p.exists():
    raise SystemExit(f"missing {p}")

reg = os.environ["SYNAPSE_REGISTRATION_SHARED_SECRET"]
pg = os.environ["POSTGRES_PASSWORD"]

t = p.read_text()
t = re.sub(r"^registration_shared_secret:.*", f'registration_shared_secret: "{reg}"', t, flags=re.M)
t = re.sub(r"^enable_registration:.*", "enable_registration: false", t, flags=re.M)
if "public_baseurl:" not in t:
    t = t.replace(
        'server_name: "bridge.flip2burn.online"',
        'server_name: "bridge.flip2burn.online"\npublic_baseurl: "https://bridge.flip2burn.online/"',
    )
else:
    t = re.sub(
        r"^public_baseurl:.*",
        'public_baseurl: "https://bridge.flip2burn.online/"',
        t,
        flags=re.M,
    )

db_block = f"""database:
  name: psycopg2
  args:
    user: synapse
    password: "{pg}"
    database: synapse
    host: postgres
    cp_min: 5
    cp_max: 10
"""
t = re.sub(r"database:.*?(?=\nlog_config:)", db_block, t, count=1, flags=re.S)
p.write_text(t)
print("PATCHED", p)

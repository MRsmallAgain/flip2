#!/usr/bin/env python3
"""Add app_service_config_files entries to Synapse homeserver.yaml in volume."""
import pathlib
import re

list_path = pathlib.Path("/tmp/list")
homeserver = pathlib.Path("/data/homeserver.yaml")
bridges = [ln.strip() for ln in list_path.read_text().splitlines() if ln.strip()]

if not bridges:
    raise SystemExit("no bridges registered")

t = homeserver.read_text()
entries = "\n".join(f"  - /data/appservices/{b}.yaml" for b in bridges)
block = f"app_service_config_files:\n{entries}\n"

if "app_service_config_files:" in t:
    t = re.sub(
        r"app_service_config_files:\n(?:  - .+\n)*",
        block,
        t,
        count=1,
    )
else:
    t = t.rstrip() + "\n\n" + block

homeserver.write_text(t)
print("patched appservices:", bridges)

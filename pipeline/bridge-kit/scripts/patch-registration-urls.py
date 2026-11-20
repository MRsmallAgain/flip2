#!/usr/bin/env python3
"""Fix appservice registration URL for Docker (Synapse container -> bridge service name)."""
import os
import pathlib
import re

reg_path = pathlib.Path(os.environ["REG_PATH"])
url = os.environ["APPSERVICE_URL"]
t = reg_path.read_text()
t = re.sub(r"^url:.*", f"url: {url}", t, count=1, flags=re.M)
reg_path.write_text(t)
print("patched", reg_path, "->", url)

#!/usr/bin/env python3

# Simple script to enter the necessary boot mode in the MT6572-based (etc) phones
# Depends on pyserial, otherwise fully cross-platform

# Usage: python3 mtk-bootseq.py [MODECMD] [port]
# e.g. python3 mtk-bootseq.py FASTBOOT /dev/tty.usbmodem14200
# and then connect the cable and repeatedly short-press the power on key

# Supported commands depend on the device and its preloader. Here's the list for Sigma S3500 sKai:
# FASTBOOT enters fastboot mode
# METAMETA enters MAUI META mode
# FACTFACT enters (Chinese) factory menu
# FACTORYM enters ATE Signaling Test
# ADVEMETA does normal boot (probably something else as well)

import sys
import time
from serial import Serial


BOOTSEQ = bytes(sys.argv[1], "ascii")
DEVICE = sys.argv[2]
CONFIRM = b"READY" + BOOTSEQ[:-4:-1]

while True:
    try:
        s = Serial(DEVICE, 115200)
        sys.stdout.write("\n")
        break
    except OSError as e:
        sys.stdout.write("."); sys.stdout.flush()
        time.sleep(0.1)
while True:
    s.write(BOOTSEQ)
    resp = s.read(8)
    print(resp)
    if resp == CONFIRM:
        break
print("Boot sequence sent")

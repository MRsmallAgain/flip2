#!/usr/bin/env python3
# Linux port of flip2 autobooter (Windows autobooter.py uses winreg).
# Watches for MTK Preloader USB 0e8d:2000 and sends FASTBOOT boot sequence.

import glob
import sys
import time
from serial import Serial

try:
    from serial.tools import list_ports
except ImportError:
    list_ports = None

MTK_VID = 0x0E8D
MTK_PID = 0x2000


def mtk_ports():
    found = []
    if list_ports:
        for p in list_ports.comports():
            if p.vid == MTK_VID and p.pid == MTK_PID and p.device:
                found.append(p.device)
    for dev in sorted(set(glob.glob("/dev/ttyACM*") + glob.glob("/dev/ttyUSB*"))):
        if dev not in found:
            found.append(dev)
    return found


def try_port(device, bootseq):
    confirm = b"READY" + bytes(bootseq[:-4:-1], "ascii")
    try:
        s = Serial(device, 115200, timeout=0.5)
        print(f"\nConnected {device}. Sending {bootseq}", flush=True)
        s.write(bytes(bootseq, "ascii"))
        resp = s.read(8)
        s.close()
        if resp == confirm:
            print(f"Entered fastboot mode on {device}", flush=True)
            sys.exit(0)
        if resp:
            print(f"Unknown response {resp!r} on {device}", flush=True)
            return 99
    except OSError:
        print(".", end="", flush=True)
    return None


def main():
    bootseq = sys.argv[1] if len(sys.argv) > 1 else "FASTBOOT"
    print("Have USB attached, then remove/reinsert battery or tap power.", flush=True)
    print("Waiting for MTK preloader (0e8d:2000) / ttyACM...", flush=True)
    while True:
        ports = mtk_ports()
        for dev in ports:
            code = try_port(dev, bootseq)
            if code == 99:
                sys.exit(99)
        time.sleep(0.1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nCanceled.", flush=True)
        sys.exit(101)

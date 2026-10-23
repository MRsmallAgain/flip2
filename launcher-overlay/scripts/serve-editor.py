#!/usr/bin/env python3
"""Local editor + adb bridge for Flip2 launcher RRO. Bind 8765; use adb reverse for in-phone Vivaldi."""
from __future__ import annotations

import json
import os
import subprocess
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
STRINGS = ROOT / "res" / "values" / "strings.xml"
BOOLS = ROOT / "res" / "values" / "bools.xml"
ARRAYS = ROOT / "res" / "values" / "arrays.xml"
SLOTS = ROOT / "slots.json"
WWW = ROOT / "www"
PORT = int(os.environ.get("FLIP2_EDITOR_PORT", "8765"))

MENU_ARRAYS = ("allapp_list", "tools_list", "tools_hasmusic_list")

_HOME = Path.home()
_BUILD_ENV = {
    **os.environ,
    "JAVA_HOME": os.environ.get("JAVA_HOME", str(_HOME / ".local/opt/jdk")),
    "ANDROID_SDK_ROOT": os.environ.get(
        "ANDROID_SDK_ROOT", str(_HOME / ".local/share/android-sdk")
    ),
}
_bt = _HOME / ".local/share/android-sdk/build-tools/34.0.0"
_BUILD_ENV["PATH"] = ":".join(
    [
        _BUILD_ENV["JAVA_HOME"] + "/bin",
        str(_bt),
        str(_HOME / ".local/bin"),
        os.environ.get("PATH", ""),
    ]
)


def run(cmd: list[str], timeout: int = 300) -> tuple[int, str]:
    try:
        p = subprocess.run(
            cmd,
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=_BUILD_ENV,
        )
        out = (p.stdout or "") + (p.stderr or "")
        return p.returncode, out.strip()
    except subprocess.TimeoutExpired:
        return -1, "timeout"
    except FileNotFoundError as e:
        return -1, str(e)


def parse_string_arrays(xml_path: Path) -> dict[str, list[str]]:
    if not xml_path.is_file():
        return {n: [] for n in MENU_ARRAYS}
    root = ET.parse(xml_path).getroot()
    out: dict[str, list[str]] = {n: [] for n in MENU_ARRAYS}
    for arr in root.findall("string-array"):
        name = arr.get("name")
        if name not in out:
            continue
        out[name] = [(el.text or "").strip() for el in arr.findall("item")]
    return out


def write_string_arrays(xml_path: Path, data: dict[str, list[str]]) -> None:
    xml_path.parent.mkdir(parents=True, exist_ok=True)
    lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
    for name in MENU_ARRAYS:
        items = data.get(name) or []
        lines.append(f'    <string-array name="{name}">')
        for item in items:
            esc = (
                item.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace('"', "&quot;")
            )
            lines.append(f"        <item>{esc}</item>")
        lines.append("    </string-array>")
        lines.append("")
    lines.append("</resources>")
    lines.append("")
    xml_path.write_text("\n".join(lines), encoding="utf-8")


def fetch_installed_packages() -> list[dict[str, str]]:
    rc, out = run(["adb", "shell", "pm", "list", "packages"], timeout=60)
    if rc != 0:
        return []
    pkgs = sorted(
        {
            ln.replace("package:", "").strip()
            for ln in out.splitlines()
            if ln.startswith("package:")
        }
    )
    result: list[dict[str, str]] = []
    for pkg in pkgs:
        label = pkg.rsplit(".", 1)[-1]
        result.append({"package": pkg, "label": label})
    return result


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _json(self, code: int, obj: dict):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> bytes:
        n = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(n) if n else b""

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            fp = WWW / "index.html"
            if not fp.is_file():
                self.send_error(404)
                return
            data = fp.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path == "/api/strings":
            if not STRINGS.is_file():
                self._json(200, {"content": '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>\n'})
                return
            self._json(200, {"content": STRINGS.read_text(encoding="utf-8")})
            return
        if path == "/api/bools":
            if not BOOLS.is_file():
                self._json(200, {"content": '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>\n'})
                return
            self._json(200, {"content": BOOLS.read_text(encoding="utf-8")})
            return
        if path == "/api/arrays":
            data = parse_string_arrays(ARRAYS)
            content = ARRAYS.read_text(encoding="utf-8") if ARRAYS.is_file() else ""
            self._json(200, {"content": content, "lists": data})
            return
        if path == "/api/packages":
            self._json(200, {"packages": fetch_installed_packages()})
            return
        if path in ("/edit", "/edit.html"):
            fp = WWW / "edit.html"
            if not fp.is_file():
                self.send_error(404)
                return
            data = fp.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path == "/api/slots":
            if not SLOTS.is_file():
                self._json(200, {"slots": {}})
                return
            try:
                slots = json.loads(SLOTS.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                self._json(500, {"error": "invalid slots.json"})
                return
            self._json(200, {"slots": slots})
            return
        self.send_error(404)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/strings":
            try:
                data = json.loads(self._read_body().decode() or "{}")
            except json.JSONDecodeError:
                self._json(400, {"error": "invalid json"})
                return
            content = data.get("content")
            if content is None:
                self._json(400, {"error": "missing content"})
                return
            STRINGS.parent.mkdir(parents=True, exist_ok=True)
            STRINGS.write_text(content, encoding="utf-8")
            self._json(200, {"ok": True})
            return
        if path == "/api/bools":
            try:
                data = json.loads(self._read_body().decode() or "{}")
            except json.JSONDecodeError:
                self._json(400, {"error": "invalid json"})
                return
            content = data.get("content")
            if content is None:
                self._json(400, {"error": "missing content"})
                return
            BOOLS.parent.mkdir(parents=True, exist_ok=True)
            BOOLS.write_text(content, encoding="utf-8")
            self._json(200, {"ok": True})
            return
        if path == "/api/arrays":
            try:
                data = json.loads(self._read_body().decode() or "{}")
            except json.JSONDecodeError:
                self._json(400, {"error": "invalid json"})
                return
            lists = data.get("lists")
            if isinstance(lists, dict):
                write_string_arrays(ARRAYS, lists)
            elif data.get("content") is not None:
                ARRAYS.parent.mkdir(parents=True, exist_ok=True)
                ARRAYS.write_text(data["content"], encoding="utf-8")
            else:
                self._json(400, {"error": "missing lists or content"})
                return
            self._json(200, {"ok": True})
            return
        if path == "/api/build-install":
            script = ROOT / "scripts" / "sign-and-install.sh"
            rc, out = run(["bash", str(script)], timeout=600)
            if rc != 0:
                self._json(500, {"error": "build failed", "output": out})
                return
            self._json(200, {"output": out})
            return
        if path == "/api/apply-on-phone":
            script = ROOT / "scripts" / "after-root-enable.sh"
            rc, out = run(["bash", str(script)], timeout=120)
            if rc != 0:
                self._json(500, {"error": "apply failed", "output": out})
                return
            self._json(200, {"output": out})
            return
        if path == "/api/slots":
            try:
                data = json.loads(self._read_body().decode() or "{}")
            except json.JSONDecodeError:
                self._json(400, {"error": "invalid json"})
                return
            slots = data.get("slots")
            if not isinstance(slots, dict):
                self._json(400, {"error": "missing slots object"})
                return
            merged = {}
            if SLOTS.is_file():
                try:
                    merged = json.loads(SLOTS.read_text(encoding="utf-8"))
                except json.JSONDecodeError:
                    merged = {}
            for k, v in slots.items():
                if k.startswith("_"):
                    continue
                if v is None or (isinstance(v, str) and not v.strip()):
                    merged.pop(k, None)
                else:
                    merged[k] = str(v).strip()
            SLOTS.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
            if data.get("apply"):
                script = ROOT / "scripts" / "apply-slots.sh"
                rc, out = run(["bash", str(script)], timeout=600)
                if rc != 0:
                    self._json(500, {"error": "apply failed", "output": out})
                    return
                self._json(200, {"ok": True, "output": out})
                return
            self._json(200, {"ok": True})
            return
        if path == "/api/adb":
            try:
                data = json.loads(self._read_body().decode() or "{}")
            except json.JSONDecodeError:
                self._json(400, {"error": "invalid json"})
                return
            args = data.get("args") or []
            if any(a in (";", "&", "|", "`", "$") for a in args):
                self._json(400, {"error": "invalid args"})
                return
            rc, out = run(["adb", *args], timeout=120)
            self._json(200, {"returncode": rc, "output": out})
            return
        self.send_error(404)


def main():
    STRINGS.parent.mkdir(parents=True, exist_ok=True)
    if not STRINGS.is_file():
        STRINGS.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>\n',
            encoding="utf-8",
        )
    print(f"Flip2 overlay editor: http://127.0.0.1:{PORT}")
    print(f"In-phone Vivaldi: adb reverse tcp:{PORT} tcp:{PORT} then open same URL on device")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()

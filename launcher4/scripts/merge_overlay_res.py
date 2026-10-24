#!/usr/bin/env python3
"""Merge launcher-overlay values into decoded APK without replacing whole strings.xml."""
import re
import sys
from pathlib import Path


def merge_string_array(target_path: Path, overlay_path: Path, name: str) -> bool:
    if not overlay_path.is_file() or not target_path.is_file():
        return False
    ot = overlay_path.read_text(encoding="utf-8")
    m = re.search(
        rf'<string-array name="{re.escape(name)}">.*?</string-array>',
        ot,
        re.DOTALL,
    )
    if not m:
        return False
    block = m.group(0)
    text = target_path.read_text(encoding="utf-8")
    pat = rf'<string-array name="{re.escape(name)}">.*?</string-array>'
    if re.search(pat, text, re.DOTALL):
        text = re.sub(pat, block, text, count=1, flags=re.DOTALL)
    else:
        text = text.replace("<resources>", "<resources>\n" + block + "\n", 1)
    target_path.write_text(text, encoding="utf-8")
    return True


def upsert_tag_entries(target_path: Path, overlay_path: Path, tag: str) -> int:
    if not target_path.is_file() or not overlay_path.is_file():
        return 0
    text = target_path.read_text(encoding="utf-8")
    overlay = overlay_path.read_text(encoding="utf-8")
    pat = re.compile(rf"<{tag}\s+name=\"([^\"]+)\"[^>]*>.*?</{tag}>", re.DOTALL)
    n = 0
    for m in pat.finditer(overlay):
        name = m.group(1)
        block = m.group(0).strip()
        existing = re.compile(
            rf"\s*<{tag}\s+name=\"{re.escape(name)}\"[^>]*>.*?</{tag}>\s*",
            re.DOTALL,
        )
        if existing.search(text):
            text = existing.sub("\n    " + block + "\n", text, count=1)
        else:
            text = text.replace("</resources>", "    " + block + "\n</resources>", 1)
        n += 1
    target_path.write_text(text, encoding="utf-8")
    return n


def main() -> None:
    work_vals = Path(sys.argv[1]) / "res" / "values"
    overlay_vals = Path(sys.argv[2]) / "values"

    arrays = work_vals / "arrays.xml"
    overlay_arrays = overlay_vals / "arrays.xml"
    if arrays.is_file() and overlay_arrays.is_file():
        for arr in ("allapp_list", "tools_list", "tools_hasmusic_list"):
            if merge_string_array(arrays, overlay_arrays, arr):
                print(f"merge-overlay: arrays.xml {arr}")

    strings_dst = work_vals / "strings.xml"
    overlay_strings = overlay_vals / "strings.xml"
    if strings_dst.is_file() and overlay_strings.is_file():
        n = upsert_tag_entries(strings_dst, overlay_strings, "string")
        print(f"merge-overlay: strings.xml patched {n} keys from overlay")
        s = strings_dst.read_text(encoding="utf-8")
        if re.search(r'name="app_name"', s):
            s = re.sub(
                r'(<string name="app_name">)[^<]*(</string>)',
                r"\1Flip2 Launcher4\2",
                s,
                count=1,
            )
        else:
            s = s.replace(
                "</resources>",
                '    <string name="app_name">Flip2 Launcher4</string>\n</resources>',
                1,
            )
        strings_dst.write_text(s, encoding="utf-8")

    res_dir = work_vals.parent
    overlay_text = overlay_strings.read_text(encoding="utf-8") if overlay_strings.is_file() else ""
    bar_keys = ("notice", "menu", "shortcuts")
    locale_count = 0
    for strings_path in res_dir.glob("values*/strings.xml"):
        if strings_path.parent.name == "values":
            continue
        s = strings_path.read_text(encoding="utf-8")
        changed = False
        for name in bar_keys:
            m = re.search(
                rf'<string name="{re.escape(name)}">([^<]*)</string>',
                overlay_text,
            )
            if not m:
                continue
            val = m.group(1)
            if not re.search(rf'name="{re.escape(name)}"', s):
                continue
            line = f'    <string name="{name}">{val}</string>'
            new_s = re.sub(
                rf'\s*<string name="{re.escape(name)}"[^>]*>[^<]*</string>\s*',
                "\n" + line + "\n",
                s,
                count=1,
            )
            if new_s != s:
                s = new_s
                changed = True
        if changed:
            strings_path.write_text(s, encoding="utf-8")
            locale_count += 1
    if locale_count:
        print(f"merge-overlay: synced notice/menu/shortcuts in {locale_count} locale strings.xml")

    bools_dst = work_vals / "bools.xml"
    overlay_bools = overlay_vals / "bools.xml"
    if bools_dst.is_file() and overlay_bools.is_file():
        n = upsert_tag_entries(bools_dst, overlay_bools, "bool")
        print(f"merge-overlay: bools.xml patched {n} keys from overlay")

    dimens_dst = work_vals / "dimens.xml"
    overlay_dimens = overlay_vals / "dimens.xml"
    if dimens_dst.is_file() and overlay_dimens.is_file():
        n = upsert_tag_entries(dimens_dst, overlay_dimens, "dimen")
        print(f"merge-overlay: dimens.xml patched {n} keys from overlay")

    overlay_root = Path(sys.argv[2]).parent
    overlay_res = Path(sys.argv[2])
    overlay_xml = overlay_root / "device_profiles.xml"
    if not overlay_xml.is_file():
        overlay_xml = overlay_res / "xml" / "device_profiles.xml"
    work_xml = res_dir / "xml" / "device_profiles.xml"
    if overlay_xml.is_file():
        work_xml.parent.mkdir(parents=True, exist_ok=True)
        work_xml.write_text(overlay_xml.read_text(encoding="utf-8"), encoding="utf-8")
        print("merge-overlay: device_profiles.xml replaced from overlay")

    overlay_layout = overlay_res / "layout"
    work_layout = res_dir / "layout"
    if overlay_layout.is_dir() and work_layout.is_dir():
        layout_n = 0
        for src in overlay_layout.glob("*.xml"):
            dst = work_layout / src.name
            if dst.is_file():
                dst.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
                layout_n += 1
        if layout_n:
            print(f"merge-overlay: layout patched {layout_n} files from overlay")

    overlay_drawable = overlay_res / "drawable"
    work_drawable = res_dir / "drawable"
    if overlay_drawable.is_dir():
        work_drawable.mkdir(parents=True, exist_ok=True)
        drawable_n = 0
        for src in overlay_drawable.glob("*.xml"):
            dst = work_drawable / src.name
            dst.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
            drawable_n += 1
        if drawable_n:
            print(f"merge-overlay: drawable patched {drawable_n} files from overlay")


if __name__ == "__main__":
    main()

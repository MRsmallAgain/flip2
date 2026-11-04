#!/usr/bin/env python3
"""Minimal LP super extract/repack for flip2 merge-super (4058G-style single super)."""
from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import struct
import sys

LP_METADATA_HEADER_MAGIC = 0x414C5030
LP_PARTITION_RESERVED_BYTES = 4096
SECTOR = 512


def sha256_bytes(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def parse_header(hdr: bytes) -> dict:
    magic, major, minor, hdr_size = struct.unpack("<IHHI", hdr[0:12])
    if magic != LP_METADATA_HEADER_MAGIC:
        raise ValueError(f"bad LP magic {magic:#x}")
    tables_size = struct.unpack("<I", hdr[44:48])[0]
    p_off, p_n, p_es = struct.unpack("<III", hdr[80:92])
    e_off, e_n, e_es = struct.unpack("<III", hdr[92:104])
    return {
        "major": major,
        "minor": minor,
        "hdr_size": hdr_size,
        "tables_size": tables_size,
        "p_off": p_off,
        "p_n": p_n,
        "p_es": p_es,
        "e_off": e_off,
        "e_n": e_n,
        "e_es": e_es,
    }


def metadata_copy_offsets(geometry: bytes) -> list[int]:
    meta_max, slot_count, _block = struct.unpack("<III", geometry[40:52])
    base = LP_PARTITION_RESERVED_BYTES * 3
    off = base
    copies = []
    for _ in range(slot_count * 2):
        copies.append(off)
        off += meta_max
    return copies


def read_geometry(super_path: str) -> bytes:
    with open(super_path, "rb") as f:
        f.seek(LP_PARTITION_RESERVED_BYTES)
        return f.read(52)


def load_metadata(super_path: str, meta_offset: int = 12288) -> tuple[bytearray, bytearray, dict]:
    with open(super_path, "rb") as f:
        f.seek(meta_offset)
        hdr = bytearray(f.read(256))
        info = parse_header(hdr)
        f.seek(meta_offset + info["hdr_size"])
        tables = bytearray(f.read(info["tables_size"]))
    return hdr, tables, info


def partition_names(tables: bytes, info: dict) -> list[str]:
    names = []
    for i in range(info["p_n"]):
        pe = tables[info["p_off"] + i * info["p_es"] : info["p_off"] + (i + 1) * info["p_es"]]
        names.append(pe[0:36].split(b"\0")[0].decode())
    return names


def extent_for_partition(tables: bytes, info: dict, part_index: int) -> tuple[int, int]:
    pe = tables[
        info["p_off"] + part_index * info["p_es"] : info["p_off"] + (part_index + 1) * info["p_es"]
    ]
    _attrs, first_ext, num_ext, _gi = struct.unpack("<IIII", pe[36:52])
    if num_ext != 1:
        raise ValueError(f"partition {part_index}: expected 1 extent, got {num_ext}")
    ee = tables[
        info["e_off"] + first_ext * info["e_es"] : info["e_off"] + (first_ext + 1) * info["e_es"]
    ]
    num_sectors, target_type, target_data, target_source = struct.unpack("<QIQI", ee[0:24])
    if target_type != 0:
        raise ValueError("non-linear extent not supported")
    return int(target_data), int(num_sectors)


def update_extent_sectors(tables: bytearray, info: dict, part_index: int, new_sectors: int) -> None:
    pe_off = info["p_off"] + part_index * info["p_es"]
    pe = tables[pe_off : pe_off + info["p_es"]]
    _attrs, first_ext, num_ext, _gi = struct.unpack("<IIII", pe[36:52])
    ee_off = info["e_off"] + first_ext * info["e_es"]
    ee = bytearray(tables[ee_off : ee_off + info["e_es"]])
    struct.pack_into("<Q", ee, 0, new_sectors)
    tables[ee_off : ee_off + info["e_es"]] = ee


def reserialize_header(hdr: bytearray, tables: bytes, hdr_size: int) -> bytes:
    tables_bytes = bytes(tables)
    struct.pack_into("<I", hdr, 44, len(tables_bytes))
    hdr[48:80] = sha256_bytes(tables_bytes)
    hdr[12:44] = b"\0" * 32
    hdr[12:44] = sha256_bytes(bytes(hdr[:hdr_size]))
    return bytes(hdr[:hdr_size]) + tables_bytes


def cmd_extract(args: argparse.Namespace) -> int:
    geom = read_geometry(args.super_img)
    copies = metadata_copy_offsets(geom)
    meta_off = copies[0]
    _hdr, tables, info = load_metadata(args.super_img, meta_off)
    names = partition_names(tables, info)
    os.makedirs(args.out_dir, exist_ok=True)
    with open(args.super_img, "rb") as f:
        for i, name in enumerate(names):
            if args.only and name not in args.only:
                continue
            td, ns = extent_for_partition(tables, info, i)
            size = ns * SECTOR
            f.seek(td * SECTOR)
            data = f.read(size)
            out = os.path.join(args.out_dir, f"{name}.img")
            with open(out, "wb") as o:
                o.write(data)
            print(f"extracted {name}: {size} bytes -> {out}")
    return 0


def cmd_repack(args: argparse.Namespace) -> int:
    work_super = args.super_img
    if args.out and args.out != args.super_img:
        shutil.copy2(args.super_img, args.out)
        work_super = args.out

    geom = read_geometry(work_super)
    copies = metadata_copy_offsets(geom)
    meta_max = struct.unpack("<I", geom[40:44])[0]
    meta_off = copies[0]
    hdr, tables, info = load_metadata(work_super, meta_off)
    names = partition_names(tables, info)

    part_images: dict[str, str] = {}
    for p in args.partition:
        if "=" not in p:
            sys.exit(f"bad --partition (want name=path): {p}")
        n, path = p.split("=", 1)
        part_images[n] = path

    with open(work_super, "r+b") as f:
        for i, name in enumerate(names):
            if name not in part_images:
                continue
            img_path = part_images[name]
            img_size = os.path.getsize(img_path)
            if img_size % SECTOR:
                sys.exit(f"{img_path}: size not sector-aligned")
            new_sectors = img_size // SECTOR
            td, old_sectors = extent_for_partition(tables, info, i)
            if new_sectors > old_sectors and not args.allow_larger:
                sys.exit(
                    f"{name}: image {img_size} exceeds LP extent {old_sectors * SECTOR} "
                    "(use --allow-larger after resize2fs)"
                )
            if new_sectors > old_sectors:
                need_end = (td + new_sectors) * SECTOR
                f.seek(0, os.SEEK_END)
                cur = f.tell()
                if need_end > cur:
                    f.truncate(need_end)
                    print(f"extended super to {need_end} bytes for {name}")
            update_extent_sectors(tables, info, i, new_sectors)
            f.seek(td * SECTOR)
            with open(img_path, "rb") as img:
                shutil.copyfileobj(img, f, length=8 * 1024 * 1024)
            if new_sectors < old_sectors:
                pad = (old_sectors - new_sectors) * SECTOR
                f.write(b"\0" * pad)
            print(f"wrote {name} at sector {td} ({img_size} bytes, extent sectors {new_sectors})")

        blob = reserialize_header(hdr, tables, info["hdr_size"])
        for off in copies:
            f.seek(off)
            f.write(blob)
            if len(blob) < meta_max:
                f.write(b"\0" * (meta_max - len(blob)))
        print(f"updated {len(copies)} metadata copies")

    if args.out:
        print(f"-> {args.out}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="flip2 LP super helper")
    sub = ap.add_subparsers(dest="cmd", required=True)
    ex = sub.add_parser("extract", help="extract logical partitions to lp/")
    ex.add_argument("super_img")
    ex.add_argument("-o", "--out-dir", required=True)
    ex.add_argument("--only", nargs="*", help="partition names")
    ex.set_defaults(func=cmd_extract)

    rp = sub.add_parser("repack", help="write partition images into super + patch LP metadata")
    rp.add_argument("super_img", help="source super (modified in place unless --out)")
    rp.add_argument("-p", "--partition", action="append", default=[], help="name=path.img")
    rp.add_argument("--out", help="output super path (copies stock first)")
    rp.add_argument(
        "--allow-larger",
        action="store_true",
        help="allow partition image larger than stock LP extent (grows super file)",
    )
    rp.set_defaults(func=cmd_repack)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

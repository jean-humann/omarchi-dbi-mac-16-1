#!/usr/bin/env python3
"""Rebase linux-t2-mbp161 packaging onto a linux-t2-arch tree.

Copies pkgver/pkgrel, T2_PATCH_HASH, kernel/t2linux checksums, and
config.x86_64 from upstream. Keeps pkgbase, yuters 0001–0005, CONFIG_RUST
off, no provides=(linux), no htmldocs.
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

ARRAY_RE = re.compile(
    r"^((?:sha256|b2)sums(?:_x86_64)?)\s*=\s*\((.*?)\)",
    re.S | re.M,
)
ITEM_RE = re.compile(r"'[^']*'|\"[^\"]*\"|SKIP")
YUTERS_COUNT = 5


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def read(path: Path) -> str:
    if not path.is_file():
        die(f"missing {path}")
    return path.read_text()


def field(text: str, key: str) -> str:
    m = re.search(rf"^{re.escape(key)}=(.*)$", text, re.M)
    if not m:
        die(f"no {key}= in PKGBUILD")
    return m.group(1).strip()


def items(body: str) -> list[str]:
    return ITEM_RE.findall(body)


def format_array(name: str, vals: list[str]) -> str:
    inner = "\n".join(f"  {v}" for v in vals)
    return f"{name}=({inner})"


def replace_arrays(dest: str, upstream: str) -> str:
    dest_map = {m.group(1): items(m.group(2)) for m in ARRAY_RE.finditer(dest)}
    up_map = {m.group(1): items(m.group(2)) for m in ARRAY_RE.finditer(upstream)}

    def swap(m: re.Match[str]) -> str:
        name = m.group(1)
        ours = dest_map.get(name, [])
        theirs = up_map.get(name, [])
        if not theirs:
            return m.group(0)
        if name.endswith("_x86_64"):
            merged = theirs
        else:
            if len(ours) < YUTERS_COUNT:
                die(f"{name}: destination PKGBUILD missing yuters checksums")
            merged = theirs + ours[-YUTERS_COUNT:]
        return format_array(name, merged)

    out, n = ARRAY_RE.subn(swap, dest)
    if n < 1:
        die("no checksum arrays in destination PKGBUILD")
    return out


def replace_assign(text: str, key: str, value: str) -> str:
    new, n = re.subn(rf"^{re.escape(key)}=.*$", f"{key}={value}", text, count=1, flags=re.M)
    if n != 1:
        die(f"could not replace {key}=")
    return new


def refresh_banner(text: str, pkgver: str, pkgrel: str, commit: str) -> str:
    nv = f"{pkgver}-{pkgrel}"
    text = re.sub(
        r"^# linux-t2-mbp161 — stock Watanare linux-t2 .* plus yuters e77b03f",
        f"# linux-t2-mbp161 — stock Watanare linux-t2 {nv} plus yuters e77b03f",
        text,
        count=1,
        flags=re.M,
    )
    if commit:
        text = re.sub(
            r"^# Upstream packaging: NoaHimesaka1873/linux-t2-arch @ \S+ \(v[^)]+\)",
            f"# Upstream packaging: NoaHimesaka1873/linux-t2-arch @ {commit} (v{nv})",
            text,
            count=1,
            flags=re.M,
        )
    return text


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--dest", required=True, type=Path, help="kernel/ in this toolbox")
    p.add_argument("--upstream", required=True, type=Path, help="cloned linux-t2-arch")
    p.add_argument("--commit", default="", help="short upstream git sha for the banner")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    dest_pb = args.dest / "PKGBUILD"
    up_pb = args.upstream / "PKGBUILD"
    dest_cfg = args.dest / "config.x86_64"
    up_cfg = args.upstream / "config.x86_64"

    dest = read(dest_pb)
    upstream = read(up_pb)
    if not re.search(r"^pkgbase=linux-t2-mbp161\s*$", dest, re.M):
        die("destination PKGBUILD is not linux-t2-mbp161")
    if not re.search(r"^pkgbase=linux-t2\s*$", upstream, re.M):
        die("upstream PKGBUILD is not linux-t2")

    old_nv = f"{field(dest, 'pkgver')}-{field(dest, 'pkgrel')}"
    new_ver = field(upstream, "pkgver")
    new_rel = field(upstream, "pkgrel")
    new_nv = f"{new_ver}-{new_rel}"
    old_hash = field(dest, "T2_PATCH_HASH")
    new_hash = field(upstream, "T2_PATCH_HASH")

    patches = sorted(args.dest.glob("yuters-000*.patch"))
    if len(patches) != YUTERS_COUNT:
        die(f"expected {YUTERS_COUNT} yuters-000*.patch in {args.dest} (got {len(patches)})")

    out = dest
    out = replace_assign(out, "pkgver", new_ver)
    out = replace_assign(out, "pkgrel", new_rel)
    out = replace_assign(out, "T2_PATCH_HASH", new_hash)
    out = replace_arrays(out, upstream)
    out = refresh_banner(out, new_ver, new_rel, args.commit)

    cfg_changed = up_cfg.is_file() and (
        not dest_cfg.is_file() or dest_cfg.read_bytes() != up_cfg.read_bytes()
    )
    pb_changed = out != dest
    changed = pb_changed or cfg_changed

    print(f"packaging {old_nv} -> {new_nv}")
    print(f"T2_PATCH_HASH {old_hash} -> {new_hash}")
    print(f"PKGBUILD {'changed' if pb_changed else 'unchanged'}")
    print(f"config.x86_64 {'changed' if cfg_changed else 'unchanged'}")

    if args.dry_run or not changed:
        return 0 if changed else 2

    dest_pb.write_text(out)
    if cfg_changed:
        shutil.copy2(up_cfg, dest_cfg)
    return 0


if __name__ == "__main__":
    sys.exit(main())

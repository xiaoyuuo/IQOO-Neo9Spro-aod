#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""patch_apk.py —— 就地把 APK 里指定 DEX 方法的函数体改成「return true」

原理：只改 code_item 的指令区，insns_size 保持不变（多余单元填 nop），
所以 DEX 内所有偏移都不用动，只需重算 header 的 SHA1 签名与 Adler32 校验和。
改完必须 zipalign（resources.arsc 需 4 字节对齐），否则 App 加载会失败。

用法：
  python patch_apk.py in.apk out.apk
  python patch_apk.py in.apk out.apk --dex classes.dex \
      --target "Lr4/h;:Q" --target "Lr4/h;:e0" --target "Lr4/h;:f0"
"""
import argparse
import hashlib
import os
import struct
import sys
import zipfile
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dexscan as ds  # noqa: E402

RETURN_TRUE = [0x1012, 0x000F]  # const/4 v0, #1 ; return v0

DEFAULT_TARGETS = ["Lr4/h;:Q", "Lr4/h;:e0", "Lr4/h;:f0"]


def patch_dex(raw, targets):
    buf = bytearray(raw)
    d = ds.Dex(bytes(buf))
    hits = []
    for c, m, _p, co in d.methods():
        if (c, m) not in targets or not co:
            continue
        insns_size = ds.u4(bytes(buf), co + 12)
        if insns_size < 2:
            raise SystemExit("insns too small for %s->%s" % (c, m))
        start = co + 16
        code = RETURN_TRUE + [0x0000] * (insns_size - 2)
        for i, unit in enumerate(code):
            struct.pack_into('<H', buf, start + 2 * i, unit)
        hits.append((c, m, insns_size))
    return bytes(buf), hits


def fix_header(buf):
    b = bytearray(buf)
    b[12:32] = hashlib.sha1(bytes(b[32:])).digest()
    struct.pack_into('<I', b, 8, zlib.adler32(bytes(b[12:])) & 0xFFFFFFFF)
    return bytes(b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("apk_in")
    ap.add_argument("apk_out")
    ap.add_argument("--dex", default="classes.dex")
    ap.add_argument("--target", action="append",
                    help="Class;:method，可重复；默认 r4.h 的 Q/e0/f0")
    args = ap.parse_args()

    targets = set()
    for t in (args.target or DEFAULT_TARGETS):
        c, m = t.rsplit(":", 1)
        targets.add((c, m))

    zin = zipfile.ZipFile(args.apk_in)
    raw = zin.read(args.dex)
    patched, hits = patch_dex(raw, targets)
    patched = fix_header(patched)
    if not hits:
        raise SystemExit("no target method matched")
    print("patched:", hits)

    with zipfile.ZipFile(args.apk_out, "w") as zout:
        for info in zin.infolist():
            data = patched if info.filename == args.dex else zin.read(info.filename)
            zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            zi.compress_type = info.compress_type
            zi.external_attr = info.external_attr
            zi.internal_attr = info.internal_attr
            zi.create_system = info.create_system
            zout.writestr(zi, data)
    print("wrote", args.apk_out)
    print("下一步：zipalign -p -f 4 后再放回模块目录")


if __name__ == "__main__":
    main()

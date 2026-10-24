#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mkzip_ksu.py —— 把 ksu/ 目录打成 KernelSU 模块 zip（带 unix 权限位）

用法：
  python mkzip_ksu.py [源目录] [输出 zip]
默认：../ksu -> ../dist/Neo9SP_aod_ksu.zip
"""
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "ksu")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "dist", "Neo9SP_aod_ksu.zip")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
files = sorted(f for f in os.listdir(SRC) if os.path.isfile(os.path.join(SRC, f)))

with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for name in files:
        data = open(os.path.join(SRC, name), "rb").read()
        if not name.endswith(".apk") and b"\r\n" in data:
            raise SystemExit("CRLF found in " + name)
        info = zipfile.ZipInfo(name, date_time=(2026, 10, 24, 12, 0, 0))
        info.external_attr = ((0o755 if name.endswith(".sh") else 0o644) << 16)
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, data)

print("wrote", OUT, os.path.getsize(OUT), "bytes")
with zipfile.ZipFile(OUT) as z:
    for i in z.infolist():
        print("  %-24s %9dB %s" % (i.filename, i.file_size, oct((i.external_attr >> 16) & 0o777)))

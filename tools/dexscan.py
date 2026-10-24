#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dexscan.py - 轻量 DEX 静态分析器（无第三方依赖）

用法:
  python dexscan.py <apk|dex|dir> info
  python dexscan.py <apk> str    <regex>      # 搜字符串表
  python dexscan.py <apk> cls    <regex>      # 搜类描述符
  python dexscan.py <apk> mth    <regex>      # 搜方法名（带所属类）
  python dexscan.py <apk> xref   <exact-str>  # 谁在代码里 const-string 引用了这个字符串
  python dexscan.py <apk> keys                # 内置 AOD 关键键名一键扫描 + xref
  python dexscan.py <apk> pkg    <prefix>     # 列出某包下所有类

要点:
 - DEX 字符串表里类描述符是斜杠形式 Lfoo/bar/Baz;，正则请用斜杠。
 - xref 用 const-string / const-string-jumbo 指令精确匹配字符串索引，
   按官方指令宽度表逐条推进，不会因为误切指令产生假命中。
"""
import os
import re
import struct
import sys
import zipfile

# ---------------- 基础读取 ----------------

def u1(b, o):
    return b[o]

def u2(b, o):
    return struct.unpack_from('<H', b, o)[0]

def u4(b, o):
    return struct.unpack_from('<I', b, o)[0]

def suleb(b, o):
    r = 0
    n = 0
    while True:
        x = b[o]
        o += 1
        r |= (x & 0x7f) << (n * 7)
        n += 1
        if not (x & 0x80):
            break
    return r, o

def s2(b, o):
    return struct.unpack_from('<h', b, o)[0]

def pretty_type(desc):
    """'Ljava/lang/String;' -> 'java.lang.String'; '[I' -> 'int[]'"""
    if not desc:
        return desc
    dim = 0
    while desc.startswith('['):
        desc = desc[1:]
        dim += 1
    prim = {'V': 'void', 'Z': 'boolean', 'B': 'byte', 'S': 'short',
            'C': 'char', 'I': 'int', 'J': 'long', 'F': 'float', 'D': 'double'}
    if desc in prim:
        base = prim[desc]
    elif desc.startswith('L') and desc.endswith(';'):
        base = desc[1:-1].replace('/', '.')
    else:
        base = desc
    return base + '[]' * dim

def pretty_class(desc):
    return pretty_type(desc)

# 指令宽度表（单位：16-bit code unit）
_SIZE = [1] * 256

def _set(lo, hi, n):
    for i in range(lo, hi + 1):
        _SIZE[i] = n

_set(0x00, 0x01, 1); _set(0x02, 0x02, 2); _set(0x03, 0x03, 3)
_set(0x04, 0x04, 1); _set(0x05, 0x05, 2); _set(0x06, 0x06, 3)
_set(0x07, 0x07, 1); _set(0x08, 0x08, 2); _set(0x09, 0x09, 3)
_set(0x0a, 0x0d, 1); _set(0x0e, 0x11, 1)
_set(0x12, 0x12, 1); _set(0x13, 0x13, 2); _set(0x14, 0x14, 3)
_set(0x15, 0x16, 2); _set(0x17, 0x17, 3); _set(0x18, 0x18, 5); _set(0x19, 0x19, 2)
_set(0x1a, 0x1a, 2); _set(0x1b, 0x1b, 3); _set(0x1c, 0x1c, 2)
_set(0x1d, 0x1e, 1); _set(0x1f, 0x20, 2); _set(0x21, 0x21, 1)
_set(0x22, 0x23, 2); _set(0x24, 0x26, 3)
_set(0x27, 0x28, 1); _set(0x29, 0x29, 2); _set(0x2a, 0x2c, 3)
_set(0x2d, 0x31, 2); _set(0x32, 0x37, 2); _set(0x38, 0x3d, 2)
_set(0x3e, 0x43, 1)
_set(0x44, 0x51, 2); _set(0x52, 0x5f, 2); _set(0x60, 0x6d, 2)
_set(0x6e, 0x72, 3); _set(0x73, 0x73, 1); _set(0x74, 0x78, 3)
_set(0x79, 0x7a, 1); _set(0x7b, 0x8f, 1)
_set(0x90, 0xaf, 2); _set(0xb0, 0xcf, 1); _set(0xd0, 0xd7, 2); _set(0xd8, 0xe2, 2)
_set(0xe3, 0xf9, 1)
_set(0xfa, 0xfb, 4); _set(0xfc, 0xfd, 3); _set(0xfe, 0xff, 2)

# ---------------- DEX 解析 ----------------

class Dex:
    def __init__(self, data, name='classes.dex'):
        self.b = data
        self.name = name
        self._parse_header()

    def _parse_header(self):
        b = self.b
        if b[:4] != b'dex\n':
            raise ValueError('not a dex: %r' % b[:8])
        self.string_ids_size = u4(b, 0x38)
        self.string_ids_off = u4(b, 0x3C)
        self.type_ids_size = u4(b, 0x40)
        self.type_ids_off = u4(b, 0x44)
        self.proto_ids_size = u4(b, 0x48)
        self.proto_ids_off = u4(b, 0x4C)
        self.field_ids_size = u4(b, 0x50)
        self.field_ids_off = u4(b, 0x54)
        self.method_ids_size = u4(b, 0x58)
        self.method_ids_off = u4(b, 0x5C)
        self.class_defs_size = u4(b, 0x60)
        self.class_defs_off = u4(b, 0x64)
        self._strings = None
        self._types = None
        self._classes = None
        self._methods = None

    def strings(self):
        if self._strings is None:
            out = []
            b, off = self.b, self.string_ids_off
            for i in range(self.string_ids_size):
                so = u4(b, off + 4 * i)
                _, p = suleb(b, so)
                end = b.index(b'\x00', p)
                raw = b[p:end].replace(b'\xc0\x80', b'\x00')
                try:
                    out.append(raw.decode('utf-8'))
                except UnicodeDecodeError:
                    out.append(raw.decode('utf-8', 'replace'))
            self._strings = out
        return self._strings

    def types(self):
        if self._types is None:
            s = self.strings()
            self._types = [s[u4(self.b, self.type_ids_off + 4 * i)]
                           for i in range(self.type_ids_size)]
        return self._types

    def class_defs(self):
        """返回 [(descriptor, super, class_data_off)]"""
        if self._classes is None:
            t = self.types()
            out = []
            b, off = self.b, self.class_defs_off
            for i in range(self.class_defs_size):
                o = off + 32 * i
                cidx = u4(b, o)
                sidx = u4(b, o + 8)
                cdata = u4(b, o + 24)
                out.append((t[cidx], (t[sidx] if sidx != 0xFFFFFFFF else None), cdata))
            self._classes = out
        return self._classes

    def methods(self):
        """返回 [(class_desc, method_name, proto_str, code_off)]"""
        if self._methods is not None:
            return self._methods
        t = self.types()
        s = self.strings()
        out = []
        b = self.b
        for cdesc, _super, cdata in self.class_defs():
            if not cdata:
                continue
            o = cdata
            n_sf, o = suleb(b, o)
            n_if, o = suleb(b, o)
            n_dm, o = suleb(b, o)
            n_vm, o = suleb(b, o)
            for _ in range(n_sf + n_if):
                _, o = suleb(b, o)
                _, o = suleb(b, o)
            for count in (n_dm, n_vm):
                midx = 0
                for _ in range(count):
                    diff, o = suleb(b, o)
                    midx += diff
                    _acc, o = suleb(b, o)
                    code_off, o = suleb(b, o)
                    mo = self.method_ids_off + 8 * midx
                    mname = s[u4(b, mo + 4)]
                    pidx = u2(b, mo + 2)
                    po = self.proto_ids_off + 12 * pidx
                    rs = t[u4(b, po + 4)]
                    out.append((cdesc, mname, pretty_type(rs), code_off))
        self._methods = out
        return out

    def code_hits(self, target_idx):
        """返回代码里 const-string 引用 target_idx 的方法列表 [(class, method, proto)]"""
        hits = []
        b = self.b
        for cdesc, mname, proto, code_off in self.methods():
            if not code_off:
                continue
            n = u4(b, code_off + 12)
            p = code_off + 16
            end = p + 2 * n
            while p < end:
                unit = u2(b, p)
                op = unit & 0xff
                if op == 0x1a:
                    if p + 2 <= end and u2(b, p + 2) == target_idx:
                        hits.append((cdesc, mname, proto))
                        break
                elif op == 0x1b:
                    if p + 6 <= end:
                        big = u2(b, p + 2) | (u2(b, p + 4) << 16)
                        if big == target_idx:
                            hits.append((cdesc, mname, proto))
                            break
                p += 2 * _SIZE[op]
        return hits


def load_dexes(path):
    """返回 [(label, Dex)]"""
    out = []
    if os.path.isdir(path):
        for root, _dirs, files in os.walk(path):
            for f in sorted(files):
                if f.endswith('.dex'):
                    p = os.path.join(root, f)
                    with open(p, 'rb') as fp:
                        out.append((p, Dex(fp.read(), p)))
        return out
    if path.lower().endswith('.dex'):
        with open(path, 'rb') as fp:
            return [(path, Dex(fp.read(), path))]
    with zipfile.ZipFile(path) as z:
        for n in z.namelist():
            if n.endswith('.dex'):
                out.append((n, Dex(z.read(n), n)))
    return out


AOD_KEYS = [
    'full_screen_aod_enabled', 'full_screen_aod_show', 'doze_always_on',
    'use_aod_infinity', 'aod_infinity', 'vivo_keyguard_aod_state',
    'vivo_keyguard_aod_type', 'vivo_integration_aod_enable',
    'vivo_support_launcher_aod', 'vscreen_always_on', 'aod_tp_support_switch',
    'facelock_screen_doze', 'keyguard_full_aod', 'aod_full_screen',
    'full_aod', 'aod_fullscreen', 'always_on_display',
]

def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    path, mode = argv[1], argv[2]
    arg = argv[3] if len(argv) > 3 else None
    dexes = load_dexes(path)
    print('# %s -> %d dex' % (path, len(dexes)))

    if mode == 'info':
        for label, d in dexes:
            print('\n== %s' % label)
            print('  strings=%d types=%d methods=%d classes=%d'
                  % (d.string_ids_size, d.type_ids_size, d.method_ids_size, d.class_defs_size))
            pk = {}
            for c, _s, _o in d.class_defs():
                p = c[1:].split('/')[0] if c.startswith('L') else c
                pk[p] = pk.get(p, 0) + 1
            for p, n in sorted(pk.items(), key=lambda kv: -kv[1])[:15]:
                print('  %-40s %d classes' % (p, n))

    elif mode == 'str':
        rx = re.compile(arg, re.I)
        for label, d in dexes:
            for i, s in enumerate(d.strings()):
                if rx.search(s):
                    print('%s #%d %s' % (label, i, s))

    elif mode == 'cls':
        rx = re.compile(arg, re.I)
        for label, d in dexes:
            for c, sup, _ in d.class_defs():
                if rx.search(c) or (sup and rx.search(sup)):
                    print('%s %s  extends %s' % (label, pretty_class(c), pretty_type(sup) if sup else ''))

    elif mode == 'mth':
        rx = re.compile(arg, re.I)
        for label, d in dexes:
            for c, m, p, _co in d.methods():
                if rx.search(m):
                    print('%s %s -> %s(%s)' % (label, pretty_class(c), m, p))

    elif mode == 'pkg':
        pre = arg
        for label, d in dexes:
            for c, _s, _o in d.class_defs():
                if c[1:].startswith(pre):
                    print('%s %s' % (label, pretty_class(c)))

    elif mode == 'xref':
        want = arg
        for label, d in dexes:
            strs = d.strings()
            try:
                idx = strs.index(want)
            except ValueError:
                continue
            hits = d.code_hits(idx)
            if hits:
                print('\n## "%s" (%s #%d) 被 %d 处引用:' % (want, label, idx, len(hits)))
                for c, m, p in hits:
                    print('   %s -> %s(%s)' % (pretty_class(c), m, p))

    elif mode == 'keys':
        for key in AOD_KEYS:
            for label, d in dexes:
                strs = d.strings()
                try:
                    idx = strs.index(key)
                except ValueError:
                    continue
                hits = d.code_hits(idx)
                print('\n## key "%s" in %s' % (key, label))
                if not hits:
                    print('   (字符串存在但无 const-string 引用)')
                for c, m, p in hits:
                    print('   %s -> %s(%s)' % (pretty_class(c), m, p))
    else:
        print('unknown mode: %s' % mode)
        print(__doc__)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dexdis.py - 极简 DEX 反汇编器（配合 dexscan.py，无第三方依赖）

用法:
  python dexdis.py <apk> mcls <类名或正则>        # 列类的方法 + code_off
  python dexdis.py <apk> dis  <类名> [方法名]      # 反汇编（不给方法名=整个类）
  python dexdis.py <apk> callers <类名> <方法名>   # 找谁调用了这个方法（按 invoke 索引）
"""
import re
import sys

import dexscan as ds

OP = {
    0x00: 'nop', 0x01: 'move', 0x02: 'move/from16', 0x03: 'move/16',
    0x04: 'move-wide', 0x05: 'move-wide/from16', 0x06: 'move-wide/16',
    0x07: 'move-object', 0x08: 'move-object/from16', 0x09: 'move-object/16',
    0x0a: 'move-result', 0x0b: 'move-result-wide', 0x0c: 'move-result-object',
    0x0d: 'move-exception', 0x0e: 'return-void', 0x0f: 'return',
    0x10: 'return-wide', 0x11: 'return-object', 0x12: 'const/4',
    0x13: 'const/16', 0x14: 'const', 0x15: 'const/high16',
    0x16: 'const-wide/16', 0x17: 'const-wide/32', 0x18: 'const-wide',
    0x19: 'const-wide/high16', 0x1a: 'const-string', 0x1b: 'const-string/jumbo',
    0x1c: 'const-class', 0x1d: 'monitor-enter', 0x1e: 'monitor-exit',
    0x1f: 'check-cast', 0x20: 'instance-of', 0x21: 'array-length',
    0x22: 'new-instance', 0x23: 'new-array', 0x24: 'filled-new-array',
    0x25: 'filled-new-array/range', 0x26: 'fill-array-data', 0x27: 'throw',
    0x28: 'goto', 0x29: 'goto/16', 0x2a: 'goto/32', 0x2b: 'packed-switch',
    0x2c: 'sparse-switch', 0x2d: 'cmpl-float', 0x2e: 'cmpg-float',
    0x2f: 'cmpl-double', 0x30: 'cmpg-double', 0x31: 'cmp-long',
    0x32: 'if-eq', 0x33: 'if-ne', 0x34: 'if-lt', 0x35: 'if-ge',
    0x36: 'if-gt', 0x37: 'if-le', 0x38: 'if-eqz', 0x39: 'if-nez',
    0x3a: 'if-ltz', 0x3b: 'if-gez', 0x3c: 'if-gtz', 0x3d: 'if-lez',
    0x44: 'aget', 0x45: 'aget-wide', 0x46: 'aget-object', 0x47: 'aget-boolean',
    0x48: 'aget-byte', 0x49: 'aget-char', 0x4a: 'aget-short',
    0x4b: 'aput', 0x4c: 'aput-wide', 0x4d: 'aput-object', 0x4e: 'aput-boolean',
    0x4f: 'aput-byte', 0x50: 'aput-char', 0x51: 'aput-short',
    0x52: 'iget', 0x53: 'iget-wide', 0x54: 'iget-object', 0x55: 'iget-boolean',
    0x56: 'iget-byte', 0x57: 'iget-char', 0x58: 'iget-short',
    0x59: 'iput', 0x5a: 'iput-wide', 0x5b: 'iput-object', 0x5c: 'iput-boolean',
    0x5d: 'iput-byte', 0x5e: 'iput-char', 0x5f: 'iput-short',
    0x60: 'sget', 0x61: 'sget-wide', 0x62: 'sget-object', 0x63: 'sget-boolean',
    0x64: 'sget-byte', 0x65: 'sget-char', 0x66: 'sget-short',
    0x67: 'sput', 0x68: 'sput-wide', 0x69: 'sput-object', 0x6a: 'sput-boolean',
    0x6b: 'sput-byte', 0x6c: 'sput-char', 0x6d: 'sput-short',
    0x6e: 'invoke-virtual', 0x6f: 'invoke-super', 0x70: 'invoke-direct',
    0x71: 'invoke-static', 0x72: 'invoke-interface',
    0x74: 'invoke-virtual/range', 0x75: 'invoke-super/range',
    0x76: 'invoke-direct/range', 0x77: 'invoke-static/range',
    0x78: 'invoke-interface/range',
    0x90: 'add-int', 0x91: 'sub-int', 0x92: 'mul-int', 0x93: 'div-int',
    0x94: 'rem-int', 0x95: 'and-int', 0x96: 'or-int', 0x97: 'xor-int',
    0x98: 'shl-int', 0x99: 'shr-int', 0x9a: 'ushr-int',
    0x9b: 'add-long', 0x9c: 'sub-long', 0x9d: 'mul-long', 0x9e: 'div-long',
    0x9f: 'rem-long', 0xa0: 'and-long', 0xa1: 'or-long', 0xa2: 'xor-long',
    0xa3: 'shl-long', 0xa4: 'shr-long', 0xa5: 'ushr-long',
    0xab: 'add-double', 0xac: 'sub-double', 0xad: 'mul-double', 0xae: 'div-double',
    0xaf: 'rem-double',
    0xb0: 'add-int/2addr', 0xb1: 'sub-int/2addr', 0xb2: 'mul-int/2addr',
    0xb3: 'div-int/2addr', 0xb4: 'rem-int/2addr', 0xb5: 'and-int/2addr',
    0xb6: 'or-int/2addr', 0xb7: 'xor-int/2addr', 0xb8: 'shl-int/2addr',
    0xb9: 'shr-int/2addr', 0xba: 'ushr-int/2addr',
    0xd0: 'add-int/lit16', 0xd1: 'rsub-int', 0xd2: 'mul-int/lit16',
    0xd3: 'div-int/lit16', 0xd4: 'rem-int/lit16', 0xd5: 'and-int/lit16',
    0xd6: 'or-int/lit16', 0xd7: 'xor-int/lit16',
    0xd8: 'add-int/lit8', 0xd9: 'rsub-int/lit8', 0xda: 'mul-int/lit8',
    0xdb: 'div-int/lit8', 0xdc: 'rem-int/lit8', 0xdd: 'and-int/lit8',
    0xde: 'or-int/lit8', 0xdf: 'xor-int/lit8', 0xe0: 'shl-int/lit8',
    0xe1: 'shr-int/lit8', 0xe2: 'ushr-int/lit8',
    0xfe: 'const-method-handle', 0xff: 'const-method-type',
}

def _set(table, ops, fmt):
    for op in ops:
        table[op] = fmt

FMT = {}
_set(FMT, (0x00, 0x0e, 0x1d, 0x1e), '10x')
_set(FMT, range(0x3e, 0x44), '10x')
_set(FMT, (0x73, 0x79, 0x7a), '10x')
_set(FMT, range(0xe3, 0xfa), '10x')
_set(FMT, (0x01, 0x04, 0x07), '12x')
_set(FMT, (0x21,), '12x')
_set(FMT, range(0x7b, 0x90), '12x')
_set(FMT, range(0xb0, 0xd0), '12x')
_set(FMT, (0x12,), '11n')
_set(FMT, (0x0a, 0x0b, 0x0c, 0x0d, 0x0f, 0x10, 0x11), '11x')
_set(FMT, (0x28,), '10t')
_set(FMT, (0x29,), '20t')
_set(FMT, (0x2a,), '30t')
_set(FMT, (0x2b, 0x2c), '31t')
_set(FMT, (0x02, 0x05, 0x08), '22x')
_set(FMT, range(0x32, 0x38), '22t')
_set(FMT, range(0x38, 0x3e), '21t')
_set(FMT, (0x13, 0x16), '21s')
_set(FMT, (0x15, 0x19), '21h')
_set(FMT, (0x14,), '31i')
_set(FMT, (0x17,), '31i')
_set(FMT, (0x18,), '51l')
_set(FMT, (0x1a, 0x1c), '21c')
_set(FMT, (0x1b,), '31c')
_set(FMT, (0x20, 0x23), '22c')
_set(FMT, (0x1f, 0x22), '21c')
_set(FMT, range(0x52, 0x60), '22c')
_set(FMT, range(0x60, 0x6e), '22c')
_set(FMT, (0x24, 0x25, 0x26), '35c')
_set(FMT, range(0x6e, 0x73), '35c')
_set(FMT, range(0x74, 0x79), '3rc')
_set(FMT, range(0x2d, 0x32), '23x')
_set(FMT, range(0x44, 0x52), '23x')
_set(FMT, range(0x90, 0xb0), '23x')
_set(FMT, range(0xd0, 0xd8), '22s')
_set(FMT, range(0xd8, 0xe3), '22b')


class Up:
    def __init__(self, dex):
        self.d = dex
        b = dex.b
        self.b = b
        t = dex.types()
        s = dex.strings()
        self.t, self.s = t, s
        self.mrefs = []
        for i in range(dex.method_ids_size):
            o = dex.method_ids_off + 8 * i
            cidx = ds.u2(b, o)
            pidx = ds.u2(b, o + 2)
            nidx = ds.u4(b, o + 4)
            self.mrefs.append('%s->%s(%s)' % (t[cidx], s[nidx], self.proto(pidx)))
        self.frefs = []
        for i in range(dex.field_ids_size):
            o = dex.field_ids_off + 8 * i
            cidx = ds.u2(b, o)
            tidx = ds.u2(b, o + 2)
            nidx = ds.u4(b, o + 4)
            self.frefs.append('%s->%s:%s' % (t[cidx], s[nidx], t[tidx]))

    def proto(self, pidx):
        b = self.b
        po = self.d.proto_ids_off + 12 * pidx
        ret = self.t[ds.u4(b, po + 4)]
        poff = ds.u4(b, po + 8)
        params = []
        if poff:
            n = ds.u4(b, poff)
            for k in range(n):
                params.append(self.t[ds.u2(b, poff + 4 + 2 * k)])
        return ','.join(params) + ')' + ret

    def u2(self, p):
        return ds.u2(self.b, p)

    def ref_m(self, idx):
        return self.mrefs[idx] if 0 <= idx < len(self.mrefs) else '?.%d' % idx

    def ref_f(self, idx):
        return self.frefs[idx] if 0 <= idx < len(self.frefs) else '?.%d' % idx

    def args(self, op, p):
        u0 = self.u2(p)
        fmt = FMT.get(op, '10x')
        u1 = self.u2(p + 2)
        u2_ = self.u2(p + 4)
        if fmt == '10x':
            return ''
        if fmt == '12x':
            return 'v%d, v%d' % (u0 >> 8 & 0xf, u0 >> 12 & 0xf)
        if fmt == '11n':
            n = (u0 >> 12) & 0xf
            if n > 7:
                n -= 16
            return 'v%d, #%d' % ((u0 >> 8) & 0xf, n)
        if fmt == '11x':
            return 'v%d' % ((u0 >> 8) & 0xff)
        if fmt == '10t':
            n = (u0 >> 8) & 0xff
            if n > 127:
                n -= 256
            return '-> %+d' % n
        if fmt == '20t':
            return '-> %+d' % ds.s2(self.b, p + 2)
        if fmt == '30t':
            return '-> %+d' % ds.u4(self.b, p + 2)
        if fmt == '21t':
            return 'v%d, -> %+d' % ((u0 >> 8) & 0xff, ds.s2(self.b, p + 2))
        if fmt == '22t':
            return 'v%d, v%d, -> %+d' % ((u0 >> 8) & 0xf, (u0 >> 12) & 0xf, ds.s2(self.b, p + 2))
        if fmt == '31t':
            return 'v%d, -> %+d' % ((u0 >> 8) & 0xff, ds.u4(self.b, p + 2))
        if fmt == '22x':
            return 'v%d, v%d' % ((u0 >> 8) & 0xff, u1)
        if fmt == '32x':
            return 'v%d, v%d' % (u1, u2_)
        if fmt == '21s':
            return 'v%d, #%d' % ((u0 >> 8) & 0xff, ds.s2(self.b, p + 2))
        if fmt == '21h':
            return 'v%d, #0x%x' % ((u0 >> 8) & 0xff, ds.s2(self.b, p + 2) << 16)
        if fmt == '31i':
            return 'v%d, #%d' % ((u0 >> 8) & 0xff, ds.u4(self.b, p + 2))
        if fmt == '51l':
            lo = ds.u4(self.b, p + 2)
            hi = ds.u4(self.b, p + 6)
            v = (hi << 32) | lo
            return 'v%d, #%d' % ((u0 >> 8) & 0xff, v)
        if fmt == '21c':
            idx = u1
            v = (u0 >> 8) & 0xff
            if op == 0x1a:
                return 'v%d, "%s"' % (v, self.s[idx] if idx < len(self.s) else '?')
            return 'v%d, %s' % (v, self.t[idx] if idx < len(self.t) else '?')
        if fmt == '31c':
            idx = u1 | (u2_ << 16)
            return 'v%d, "%s"' % ((u0 >> 8) & 0xff, self.s[idx] if idx < len(self.s) else '?')
        if fmt == '22c':
            if op in (0x20, 0x23):
                return 'v%d, v%d, %s' % ((u0 >> 8) & 0xf, (u0 >> 12) & 0xf,
                                         self.t[u1] if u1 < len(self.t) else '?')
            return 'v%d, v%d, %s' % ((u0 >> 8) & 0xf, (u0 >> 12) & 0xf, self.ref_f(u1))
        if fmt == '22s':
            return 'v%d, v%d, #%d' % ((u0 >> 8) & 0xf, (u0 >> 12) & 0xf, ds.s2(self.b, p + 2))
        if fmt == '22b':
            lit = (u1 >> 8) & 0xff
            if lit > 127:
                lit -= 256
            return 'v%d, v%d, #%d' % ((u0 >> 8) & 0xff, u1 & 0xff, lit)
        if fmt == '23x':
            return 'v%d, v%d, v%d' % ((u0 >> 8) & 0xff, u1 & 0xff, (u1 >> 8) & 0xff)
        if fmt == '35c':
            cnt = (u0 >> 12) & 0xf
            g = (u0 >> 8) & 0xf
            idx = u1
            regs = []
            for k in range(4):
                if cnt <= k:
                    break
                regs.append('v%d' % ((u2_ >> (4 * k)) & 0xf))
            if cnt == 5:
                regs.append('v%d' % g)
            return '{%s}, %s' % (', '.join(regs), self.ref_m(idx))
        if fmt == '3rc':
            cnt = (u0 >> 8) & 0xff
            idx = u1
            start = u2_
            return '{v%d .. v%d}, %s' % (start, start + cnt - 1, self.ref_m(idx))
        return ''


def iter_methods(dex, cls_re=None, name=None):
    for cdesc, mname, proto, code_off in dex.methods():
        if cls_re is not None and not cls_re.search(ds.pretty_class(cdesc)):
            continue
        if name is not None and mname != name:
            continue
        yield cdesc, mname, proto, code_off


def dis(up, dex, cls_re, name=None, limit=None):
    n = 0
    for cdesc, mname, proto, code_off in iter_methods(dex, cls_re, name):
        print('\n.method %s->%s(%s)  code_off=0x%x' % (ds.pretty_class(cdesc), mname, proto, code_off))
        if not code_off:
            print('  (no code)')
            continue
        b = dex.b
        size = ds.u4(b, code_off + 12)
        p = code_off + 16
        end = p + 2 * size
        while p < end:
            unit = ds.u2(b, p)
            op = unit & 0xff
            nm = OP.get(op, 'op_%02x' % op)
            try:
                a = up.args(op, p)
            except Exception as e:
                a = '?err %s' % e
            print('  %-6s %-24s %s' % ('%04x' % ((p - code_off - 16) // 2), nm, a))
            p += 2 * ds._SIZE[op]
        print('.end method')
        n += 1
        if limit and n >= limit:
            return


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 1
    path, mode, target = argv[1], argv[2], argv[3]
    dexes = ds.load_dexes(path)
    if mode == 'mcls':
        rx = re.compile(target, re.I)
        for label, d in dexes:
            for c, sup, _o in d.class_defs():
                if rx.search(ds.pretty_class(c)):
                    print('\n## %s extends %s [%s]' % (ds.pretty_class(c),
                                                       ds.pretty_type(sup) if sup else '', label))
                    for c2, m, p, co in d.methods():
                        if c2 == c:
                            print('   %s(%s) code=0x%x' % (m, p, co))
    elif mode == 'dis':
        cls = target
        name = argv[4] if len(argv) > 4 else None
        for label, d in dexes:
            dis(Up(d), d, re.compile('^' + re.escape(cls) + '$'), name)
    elif mode == 'callers':
        if len(argv) < 5:
            print('need class and method')
            return 1
        want = argv[4]
        for label, d in dexes:
            up = Up(d)
            for cdesc, mname, proto, code_off in d.methods():
                if not code_off:
                    continue
                b = d.b
                size = ds.u4(b, code_off + 12)
                p = code_off + 16
                end = p + 2 * size
                while p < end:
                    op = ds.u2(b, p) & 0xff
                    if op in (0x6e, 0x6f, 0x70, 0x71, 0x72, 0x74, 0x75, 0x76, 0x77, 0x78):
                        idx = ds.u2(b, p + 2)
                        ref = up.ref_m(idx)
                        if ref.startswith(target + '->' + want + '('):
                            print('%s  <-  %s->%s(%s)' % (ref, ds.pretty_class(cdesc), mname, proto))
                            break
                    p += 2 * ds._SIZE[op]
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""Generate Kompakt/cust.dtsi from the shipping overlay's fragments 28..60."""
import re, sys
src = open(sys.argv[1]).read()
FIRST, LAST = 28, 60

# __fixups__: label -> list of (fragment, subpath, prop, byte offset)
fx = re.search(r'\n\t__fixups__ \{(.*?)\n\t\};', src, re.S).group(1)
target_of, inner = {}, {}
for lab, val in re.findall(r'\n\t\t(\S+) = "(.*?)";', fx):
    for ref in val.split('\\0'):
        m = re.match(r'/fragment@(\d+)(/__overlay__[^:]*)?:([^:]+):(\d+)$', ref)
        if not m:
            continue
        n, sub, prop, off = int(m.group(1)), m.group(2), m.group(3), int(m.group(4))
        if sub is None and prop == 'target':
            target_of[n] = lab
        else:
            inner.setdefault(n, []).append((sub, prop, off, lab))

# __symbols__: labels on child nodes inside the cust fragments.
sy = re.search(r'\n\t__symbols__ \{(.*?)\n\t\};', src, re.S).group(1)
child_label = {}
for lab, path in re.findall(r'\n\t\t(\S+) = "(.*?)";', sy):
    m = re.match(r'/fragment@(\d+)/__overlay__/([^/]+)$', path)
    if m and FIRST <= int(m.group(1)) <= LAST:
        child_label[(int(m.group(1)), m.group(2))] = lab

def block(n):
    m = re.search(r'\n\tfragment@%d \{' % n, src)
    i = src.index('{', m.start()); d = 0; k = i
    while True:
        d += {'{': 1, '}': -1}.get(src[k], 0)
        if d == 0: break
        k += 1
    frag = src[i:k+1]
    o = frag.index('__overlay__ {')
    j = frag.index('{', o); d = 0; k = j
    while True:
        d += {'{': 1, '}': -1}.get(frag[k], 0)
        if d == 0: break
        k += 1
    return frag[j+1:k]  # overlay body, without its braces

def patch_cell(line, off, lab):
    m = re.match(r'(\s*\S+ = <)([^>]*)(>;.*)', line)
    cells = m.group(2).split()
    idx = off // 4
    assert cells[idx] == '0xffffffff', (line, off, cells)
    cells[idx] = '&' + lab
    return m.group(1) + ' '.join(cells) + m.group(3)

out = ["/* Kompakt: generated from the shipping dtbo, fragments %d-%d. See dtbo/README.md. */" % (FIRST, LAST), ""]
for n in range(FIRST, LAST + 1):
    lab = target_of[n]
    lines = block(n).split('\n')
    for sub, prop, off, reflab in inner.get(n, []):
        assert sub == '/__overlay__', ('ref inside a child node', n, sub, prop)
        hits = [i for i, l in enumerate(lines)
                if re.match(r'\s*%s = <' % re.escape(prop), l) and l.startswith('\t\t\t')
                and not l.startswith('\t\t\t\t')]
        assert len(hits) == 1, ('property not found exactly once', n, prop, hits)
        lines[hits[0]] = patch_cell(lines[hits[0]], off, reflab)
    for (fn, child), clab in child_label.items():
        if fn != n:
            continue
        hits = [i for i, l in enumerate(lines) if l == '\t\t\t%s {' % child]
        assert len(hits) == 1, ('child node not found exactly once', n, child, hits)
        lines[hits[0]] = '\t\t\t%s: %s {' % (clab, child)
    body = '\n'.join(l[2:] if l.startswith('\t\t') else l for l in lines).strip('\n')
    out.append('&%s {\n%s\n};\n' % (lab, body))

assert '0xffffffff' not in '\n'.join(out), 'an unresolved phandle placeholder remains'
open(sys.argv[2], 'w').write('\n'.join(out))
print('fragments written:', LAST - FIRST + 1)
print('child labels restored:', len(child_label))
print('inner refs resolved:', sum(len(v) for k, v in inner.items() if FIRST <= k <= LAST))

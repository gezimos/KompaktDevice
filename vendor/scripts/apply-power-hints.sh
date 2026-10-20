#!/bin/bash
# Android's own power hints get the boosts MuditaOS's MediaTek hints had.
# MuditaOS's framework sends MediaTek-only hints (mediatek-framework.jar,
# PowerHalWrapper): PROCESS_CREATE on a cold start holds the full boost 6 s and
# then EXT_LAUNCH for 35 s; UX_SCROLLING keeps the CPU at 1.075 GHz or more.
# LineageOS sends only Android's: Mode LAUNCH reaches powerscntbl.xml's LAUNCH,
# which drops the boost the moment the launch ends, and every touch reaches
# MTKPOWER_HINT_APP_TOUCH (hint 25, 1 s), which only notifies the frame boost.
# APP_TOUCH takes UX_SCROLLING's CPU floor. LAUNCH only takes the frame boost:
# hold and tail do nothing there, since Android ends the mode and libPowerHal
# releases the lock at once (build 372 log), so any left on the stage are
# removed, as is an earlier INTERACTION scenario that nothing looks up.
# Usage: apply-power-hints.sh <vendor-stage-dir> (idempotent). Edits in place
# so the file keeps its SELinux label.
set -euo pipefail
V="${1:?usage: apply-power-hints.sh <vendor-stage-dir>}"
T="$V/etc/powerscntbl.xml"
test -f "$T" || { echo "no powerscntbl.xml under $V"; exit 1; }
python3 - "$T" <<'PY'
import re, sys
p = sys.argv[1]
s0 = s = open(p).read()

def block(name):
    head = '    <scenario powerhint="%s">\n' % name
    if head not in s:
        sys.exit("GATE_POWER_NO_" + name)
    b = s.index(head)
    return b, s.index('    </scenario>\n', b)

s = re.sub(r'    <scenario powerhint="INTERACTION">\n(?:        <data[^\n]*\n)*    </scenario>\n', '', s)

b, e = block("LAUNCH")
part = s[b:e]
for dead in ('        <data cmd="PERF_RES_POWER_HINT_HOLD_TIME" param1="6000"></data>\n',
             '        <data cmd="PERF_RES_POWER_HINT_EXT_HINT" param1="30"></data>\n',
             '        <data cmd="PERF_RES_POWER_HINT_EXT_HINT_HOLD_TIME" param1="35000"></data>\n'):
    part = part.replace(dead, '')
if 'FPS_FBT_BHR_OPP' not in part:
    part += '        <data cmd="PERF_RES_FPS_FBT_BHR_OPP" param1="15"></data>\n'
s = s[:b] + part + s[e:]

b, e = block("MTKPOWER_HINT_APP_TOUCH")
if 'CPUFREQ_MIN_CLUSTER_0' not in s[b:e]:
    s = s[:e] + ('        <data cmd="PERF_RES_CPUFREQ_MIN_CLUSTER_0" param1="1075000"></data>\n'
                 '        <data cmd="PERF_RES_CPUFREQ_MAX_CLUSTER_0" param1="3000000"></data>\n') + s[e:]

if s != s0:
    with open(p, 'r+') as f:
        f.seek(0); f.write(s); f.truncate()
b, e = block("LAUNCH")
print("POWER_LAUNCH_FBT=%d" % s[b:e].count('FPS_FBT_BHR_OPP'))
b, e = block("MTKPOWER_HINT_APP_TOUCH")
print("POWER_TOUCH_FLOOR=%d" % s[b:e].count('CLUSTER_0" param1="1075000"'))
print("POWER_INTERACTION=%d" % s.count('powerhint="INTERACTION"'))
PY

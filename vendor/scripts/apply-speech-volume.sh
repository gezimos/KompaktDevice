#!/bin/bash
# In-call earpiece volume, Mudita's speech levels retuned for how Android drives them.
# The audio HAL turns the call volume v (0 to 1) into speech level (int)(v*5)+1,
# so with six call steps (ro.config.vc_call_vol_steps=6) each step is one of
# levels 1 to 6: dl_gain entries 0 to 5, indexes into VolumeGainMap's RCV_NORMAL
# table, 1 dB each, +8 dB at 0. They are -28, -21, -15, -8, -2 and +5 dB;
# Mudita's loudest reachable level was +5 dB and its lowest -10 dB. Level 7 is
# never reached and stays at the top.
# Usage: apply-speech-volume.sh <vendor-stage-dir>   (idempotent)
# Edits in place so the file keeps its SELinux label.
set -euo pipefail
V="${1:?usage: apply-speech-volume.sh <vendor-stage-dir>}"
XML="$V/etc/audio_param/SpeechVol_AudioParam.xml"

python3 - "$XML" <<'EOF'
import re, sys
p = sys.argv[1]
# param_id: ((Mudita's levels, vendor 268's, 269's), ours). 0 is the receiver; 7, 8 and 9 are the
# receiver on narrow, wide and super wide band calls (VoLTE and Wi-Fi calls).
UNITS = {
    '0': (('22,19,16,13,10,7,4', '34,29,24,19,14,9,4', '40,36,28,20,11,3,3'), '36,29,23,16,10,3,3'),
    '7': (('21,18,15,12,9,6,3', '33,28,23,18,13,8,3', '40,36,28,20,11,3,3'), '36,29,23,16,10,3,3'),
    '8': (('21,18,15,12,9,6,3', '33,28,23,18,13,8,3', '40,36,28,20,11,3,3'), '36,29,23,16,10,3,3'),
    '9': (('21,18,15,12,9,6,3', '33,28,23,18,13,8,3', '40,36,28,20,11,3,3'), '36,29,23,16,10,3,3'),
}
with open(p, 'r+') as f:
    s = f.read()
    for pid, (olds, new) in UNITS.items():
        pat = re.compile(r'(<ParamUnit param_id="%s">\s*<Param name="dl_gain" value=")([0-9,]+)(")' % pid)
        m = pat.findall(s)
        if len(m) != 1:
            sys.exit('expected one ParamUnit %s, found %d' % (pid, len(m)))
        cur = m[0][1]
        if cur == new:
            print('unit', pid, 'already', new)
            continue
        if cur not in olds:
            sys.exit('unit %s dl_gain is %s, not the one this script expects' % (pid, cur))
        s = pat.sub(lambda x: x.group(1) + new + x.group(3), s)
        print('unit', pid, cur, '->', new)
    f.seek(0)
    f.write(s)
    f.truncate()
EOF

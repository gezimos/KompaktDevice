#!/bin/bash
# Ring and notification volume on the speaker use Android's default speaker
# curve. Mudita's curve only went 29.7 dB below full volume, so the lowest
# step was still loud; Android's goes 58 dB down. Full volume is unchanged.
# Usage: apply-volume-curves.sh <vendor-stage-dir>   (idempotent)
# Edits in place so the file keeps its SELinux label.
set -euo pipefail
V="${1:?usage: apply-volume-curves.sh <vendor-stage-dir>}"
XML="$V/etc/audio_policy_volumes.xml"

python3 - "$XML" <<'EOF'
import sys
p = sys.argv[1]
OLD = ('        <point>1,-2970</point>\n'
       '        <point>33,-2010</point>\n'
       '        <point>66,-1020</point>\n'
       '        <point>100,0</point>\n')
NEW = ('        <point>1,-5800</point>\n'
       '        <point>20,-4000</point>\n'
       '        <point>60,-1700</point>\n'
       '        <point>100,0</point>\n')

with open(p, 'r+') as f:
    s = f.read()
    for stream in ('AUDIO_STREAM_RING', 'AUDIO_STREAM_NOTIFICATION'):
        head = ('<volume stream="%s" deviceCategory="DEVICE_CATEGORY_SPEAKER">\n'
                % stream)
        if s.count(head) != 1:
            sys.exit('expected one %s speaker curve, found %d' % (stream, s.count(head)))
        start = s.index(head) + len(head)
        if s.startswith(NEW, start):
            print(stream, 'speaker curve already Android default')
            continue
        if not s.startswith(OLD, start):
            sys.exit('%s speaker curve is not the one this script expects' % stream)
        s = s[:start] + NEW + s[start + len(OLD):]
        print(stream, 'speaker curve set to Android default')
    f.seek(0)
    f.write(s)
    f.truncate()
EOF

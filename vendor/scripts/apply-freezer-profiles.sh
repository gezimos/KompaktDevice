#!/bin/bash
# Android's cached-app freezer works through the task profiles Frozen and
# Unfrozen and the attribute FreezerState, which /system/etc/task_profiles.json
# maps to cgroup.freeze in the cgroup v2 tree. Mudita's vendor file defines all
# three again for a cgroup v1 freezer this phone never mounts
# (frozen/freezer.state), and vendor definitions win, so Android's support
# probe found no file and logged "Freezer disabled" at every boot. This removes
# the three overrides. MediaTek's own FreezerFrozen and FreezerThawed profiles
# stay: nothing in vendor uses them.
# Usage: apply-freezer-profiles.sh <vendor-stage-dir> (idempotent). Edits in
# place so the file keeps its SELinux label.
set -euo pipefail
V="${1:?usage: apply-freezer-profiles.sh <vendor-stage-dir>}"
T="$V/etc/task_profiles.json"
test -f "$T" || { echo "no task_profiles.json under $V"; exit 1; }
python3 - "$T" <<'PY'
import json, re, sys
p = sys.argv[1]
s0 = s = open(p).read()
json.loads(s0)
for name in ("FreezerState", "Frozen", "Unfrozen"):
    # one element of Attributes or Profiles: its opening brace to the first
    # closing brace at the same indent
    s, n = re.subn(r'^    \{\n^      "Name": "%s",\n(?:^.*\n)*?^    \},?\n' % name, '', s, flags=re.M)
    if n > 1:
        sys.exit("GATE_FREEZER_DUPLICATE_" + name)
# the element before a removed last one keeps no comma
s = re.sub(r'\},\n(\s*\])', r'}\n\1', s)
d = json.loads(s)
names = {a["Name"] for a in d["Attributes"]} | {q["Name"] for q in d["Profiles"]}
left = names & {"FreezerState", "Frozen", "Unfrozen"}
if left:
    sys.exit("GATE_FREEZER_OVERRIDE_LEFT " + " ".join(sorted(left)))
if s != s0:
    with open(p, 'r+') as f:
        f.seek(0); f.write(s); f.truncate()
print("FREEZER_V1_PATH=%d" % s.count("frozen/freezer.state"))
print("FREEZER_PROFILES=%d" % len(d["Profiles"]))
PY
echo FREEZER_PROFILES_OK

#!/bin/bash
# Build the Kompakt kernel.
#
# CROSS_COMPILE must be aarch64-linux-gnu-: the android triple builds a kernel
# that never boots. Toolchain is AOSP clang-r383902. See docs/Kernel.md.
#
# Usage: ./build-kernel.sh <kernel source dir> <output dir> [patch ...]

set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

K=${1:?usage: build-kernel.sh <kernel src> <out dir> [patches...]}
O=${2:?usage: build-kernel.sh <kernel src> <out dir> [patches...]}
shift 2
TC=${TOOLCHAIN:?set TOOLCHAIN to AOSP clang-r383902}
LINEAGE=${LINEAGE:?set LINEAGE to a LineageOS tree}

export PATH=$TC/bin:$LINEAGE/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin:$PATH
# Match Mudita's build host strings.
export KBUILD_BUILD_USER=nobody KBUILD_BUILD_HOST=android-build
# KOMPAKT_BUILD sets the build number shown in /proc/version (not part of vermagic).
if [ -n "${KOMPAKT_BUILD:-}" ]; then
    export KBUILD_BUILD_USER=kompakt KBUILD_BUILD_VERSION=$KOMPAKT_BUILD
fi

cd "$K"
# vermagic must match the prebuilt modules or meink.ko will not load.
echo "-00095-g83b1ab1a9a4b-dirty" > .scmversion

for p in "$@"; do
    echo "== applying $p"
    git apply "$p"
done

M=(ARCH=arm64 O="$O" LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-)
rm -rf "$O"; mkdir -p "$O"
make "${M[@]}" Kompakt_defconfig
make -j"$(nproc)" "${M[@]}" Image.gz modules

echo "== built:"; ls -l "$O/arch/arm64/boot/Image.gz"
strings "$O/vmlinux" | grep -m1 "^Linux version"

# The prebuilt vendor modules load only if their symbol CRCs match this build.
# VENDOR_MODULES=<dir with the stock .ko files> makes this a hard gate.
if [ -n "${VENDOR_MODULES:-}" ]; then
    bad=0
    for m in meink meink_hal fmradio_drv_mt6631 wmt_drv wlan_drv_gen4m bt_drv_connac1x gps_drv mt6357-accdet; do
        out=$(python3 "$HERE/check-module-crcs.py" "$O/Module.symvers" "$VENDOR_MODULES/$m.ko")
        echo "$out"
        echo "$out" | grep -q "MISMATCH=  0" || bad=1
    done
    [ "$bad" = 0 ] || { echo "== CRC MISMATCH: these modules would not load. Do not flash."; exit 1; }
fi

# mt6761 builds the mt6765 display driver, not mt6768.
echo "== display driver object that was actually compiled:"
find "$O/drivers/misc/mediatek/video" -name primary_display.o

cat <<'NOTE'

== verify before flashing ==
1. meink.ko's 45 symbol CRCs must match this build's Module.symvers.
2. Disassemble any function you patched IN THE FINISHED IMAGE. Editing a file
   proves nothing -- a patch to the wrong platform directory compiles away
   silently and the binary comes out identical to stock.
3. Round-trip the boot image packer against stock sections first; the header
   must come out byte-identical. See docs/Device-tree.md.
NOTE

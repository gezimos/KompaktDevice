#
# BoardConfig for the Mudita Kompakt (MT6761, 480x800 e-ink).
# Values are read from the stock firmware. See docs/Device-tree.md.
#

DEVICE_PATH := device/mudita/kompakt

# -------------------------------------------------------------- architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a53

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a53

TARGET_BOARD_PLATFORM := mt6761
TARGET_BOOTLOADER_BOARD_NAME := Kompakt

# ---------------------------------------------------------------- boot image
# kernel_addr 0x40080000.
BOARD_KERNEL_BASE        := 0x40000000
BOARD_KERNEL_OFFSET      := 0x00080000
BOARD_KERNEL_PAGESIZE    := 2048
BOARD_RAMDISK_OFFSET     := 0x11b00000
BOARD_KERNEL_TAGS_OFFSET := 0x07880000
BOARD_DTB_OFFSET         := 0x07880000
BOARD_BOOT_HEADER_VERSION := 2
# Stock command line.
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 buildvariant=user

BOARD_MKBOOTIMG_ARGS += --base $(BOARD_KERNEL_BASE)
# Without this mkbootimg defaults to 0x8000 and the kernel loads at the wrong address.
BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)

# No vendor_boot on this device.
# Leave BOARD_INCLUDE_RECOVERY_DTBO unset, not false: the build tests it with ifdef.

# The kernel is built outside the platform build. See docs/Kernel.md and
# prebuilt/README.md.
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image.gz
# Must not exist, or kernel.mk ignores TARGET_PREBUILT_KERNEL and builds the source.
TARGET_KERNEL_SOURCE := $(DEVICE_PATH)/prebuilt/no-kernel-source-on-purpose
BOARD_KERNEL_IMAGE_NAME := Image.gz
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt/dtb
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img

# ------------------------------------------------------------------ recovery
# Recovery is the boot ramdisk. The e-ink modules load in recovery only, as in stock.
TARGET_RECOVERY_PIXEL_FORMAT := BGRA_8888
TARGET_RECOVERY_UI_MARGIN_WIDTH := 16
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.mt6761
BOARD_RECOVERY_KERNEL_MODULES := \
    $(DEVICE_PATH)/prebuilt/recovery-modules/meink_hal.ko \
    $(DEVICE_PATH)/prebuilt/recovery-modules/meink.ko \
    $(DEVICE_PATH)/prebuilt/recovery-modules/meink_loader.ko
BOARD_DO_NOT_STRIP_RECOVERY_MODULES := true

# --------------------------------------------------------------- partitions
# Sizes from lpdump on stock.
BOARD_SUPER_PARTITION_SIZE := 5368709120
BOARD_SUPER_PARTITION_GROUPS := mudita_dynamic_partitions
BOARD_MUDITA_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product
BOARD_MUDITA_DYNAMIC_PARTITIONS_SIZE := 5366611968

BOARD_USES_METADATA_PARTITION := true
TARGET_USES_MKE2FS := true

# ext4 only: the stock kernel has no EROFS or F2FS (docs/Kernel.md, Do not retry).
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE  := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE  := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4

TARGET_COPY_OUT_VENDOR  := vendor
TARGET_COPY_OUT_PRODUCT := product

# ------------------------------------------------------------------- A/B
AB_OTA_UPDATER := true
BOARD_USES_RECOVERY_AS_BOOT := true
TARGET_NO_RECOVERY := true

AB_OTA_PARTITIONS += \
    boot \
    dtbo \
    product \
    system \
    vbmeta \
    vbmeta_system \
    vbmeta_vendor \
    vendor

# ------------------------------------------------------------------- AVB
# The bootloader has no custom key slot, so never relock (docs/Kernel.md, "The bootloader can never be relocked").
BOARD_AVB_ENABLE := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 2
# Chained vbmeta as in stock. Test keys on purpose: nothing we sign is verified.
BOARD_AVB_VBMETA_SYSTEM := system
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 1

BOARD_AVB_VBMETA_VENDOR := vendor
BOARD_AVB_VBMETA_VENDOR_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_VENDOR_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_VENDOR_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_VENDOR_ROLLBACK_INDEX_LOCATION := 2

# --------------------------------------------------------------- properties
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop
BOARD_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy

BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor

# The GSI platform policy breaks two AOSP neverallows on purpose; recovery
# policy does not compile without this.
SELINUX_IGNORE_NEVERALLOWS := true

# Recovery adb needs a debuggable recovery, which no makefile setting gives
# here. See docs/Device-tree.md.

# ------------------------------------------------------------------- VINTF
# Verbatim from the stock vendor partition.
DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/vintf/manifest.xml
DEVICE_MATRIX_FILE   := $(DEVICE_PATH)/vintf/compatibility_matrix.xml

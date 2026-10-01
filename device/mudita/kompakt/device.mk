LOCAL_PATH := device/mudita/kompakt

# ------------------------------------------------------------------ boot
# The boot HAL comes from the blobs. android.hardware.boot@1.2-impl-ab no longer exists.

# Stock fstab. Keep the GSI avb_keys, or a Google-signed system.img will not mount.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6761:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.mt6761

# Recovery-as-boot: first_stage_ramdisk/ is inside the recovery root, not
# TARGET_COPY_OUT_RAMDISK, which is never packed.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.mt6761:$(TARGET_COPY_OUT_RECOVERY)/root/first_stage_ramdisk/fstab.mt6761

# ------------------------------------------------------------------ recovery
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init.recovery.mt6761.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt6761.rc

# Recovery /adb_keys cannot be set from here. See docs/Device-tree.md.

# ------------------------------------------------------------------ e-ink
# meink.ko comes from the blobs; meink_hal and meink_loader build from the kernel tree.

# ------------------------------------------------------------------ dynamic
PRODUCT_PACKAGES += \
    android.hardware.fastboot@1.1-impl-mock

# Recovery is also fastbootd and the sideload installer; nothing else pulls them in.
PRODUCT_PACKAGES += \
    fastbootd \
    update_engine_sideload

# Recovery has no hwservicemanager, so sideload needs the AIDL boot HAL.
# MediaTek keeps slot state in AOSP's format in misc (para).
PRODUCT_PACKAGES += \
    android.hardware.boot-service.default_recovery

# Dynamic partitions and Virtual A/B are product-level, not board-level.
PRODUCT_USE_DYNAMIC_PARTITIONS := true
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota.mk)
# compression_retrofit.mk by hand: it names snapuserd.ramdisk, which no longer exists.
PRODUCT_VENDOR_PROPERTIES += ro.virtual_ab.compression.enabled=true
PRODUCT_VIRTUAL_AB_COMPRESSION := true
PRODUCT_PACKAGES += \
    snapuserd_ramdisk \
    snapuserd \
    snapuserd.recovery

# ------------------------------------------------------------------ blobs
$(call inherit-product-if-exists, vendor/mudita/kompakt/kompakt-vendor.mk)

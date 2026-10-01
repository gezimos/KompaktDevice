# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from the device makefile.
$(call inherit-product, device/mudita/kompakt/device.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_DEVICE := kompakt
PRODUCT_NAME := lineage_kompakt
PRODUCT_BRAND := Mudita
PRODUCT_MODEL := Kompakt
PRODUCT_MANUFACTURER := Mudita

PRODUCT_GMS_CLIENTID_BASE := android-mudita

# Match the stock vendor fingerprint (Android 12).
BUILD_FINGERPRINT := Mudita/Kompakt/Kompakt:12/SP1A.210812.016/20260731:user/dev-keys

# Android 16 only accepts product-config keys here, not TARGET_DEVICE/PRODUCT_NAME.
PRODUCT_BUILD_PROP_OVERRIDES += \
    DeviceName=Kompakt \
    DeviceProduct=Kompakt

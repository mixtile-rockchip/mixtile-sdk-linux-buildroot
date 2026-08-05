#!/bin/bash -e
#
# Post-build hook for the Mixtile CORE3588E production-test image.
#
# This board does not go through focalcrest/post-build.sh: that script applies
# every overlay directory under focalcrest/overlays/, which would pull other
# boards overlays into this image. Keep CORE3588E self-contained instead.

TARGET_DIR="${TARGET_DIR:-"$@"}"

# Export configs to environment
export $(grep -E "^BR2_.*=y|^BR2_DEFCONFIG=" \
	"${BR2_CONFIG:-"$TARGET_DIR/../.config"}")

[ "$BR2_PACKAGE_RK3588" ]
[ "$BR2_PACKAGE_PRODUCTIONTOOL" ]

OVERLAY_DIR="$(dirname "$0")/overlay"

# Drop the stock configs our overlay replaces, so the overlay wins.
rm -rf "$TARGET_DIR/etc/alsa/conf.d"
rm -rf "$TARGET_DIR/etc/xdg/weston/weston.ini.d/"

echo ">>> Copying $OVERLAY_DIR"
rsync -av --chmod=u=rwX,go=rX --exclude .empty \
	"$OVERLAY_DIR/" "$TARGET_DIR/"

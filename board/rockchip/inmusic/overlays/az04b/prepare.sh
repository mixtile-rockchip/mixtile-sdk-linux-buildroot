#!/bin/bash -ex

[ "$BR2_PACKAGE_RK3588" ]
[ "$BR2_PACKAGE_PRODUCTIONTOOL" ]

rm -rf "$TARGET_DIR/etc/alsa/conf.d"
rm -rf "$TARGET_DIR/etc/xdg/weston/weston.ini.d/"

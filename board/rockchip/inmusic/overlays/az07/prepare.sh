#!/bin/bash -e

[ "$BR2_PACKAGE_RK3566_RK3568" ]
[ "$BR2_PACKAGE_PRODUCTIONTOOL" ]

rm -rf "$TARGET_DIR/etc/alsa/conf.d"
rm -rf "$TARGET_DIR/etc/xdg/weston/weston.ini.d/"

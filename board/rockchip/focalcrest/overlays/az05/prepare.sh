#!/bin/bash -e

[ "$BR2_PACKAGE_RK3288" ]

rm -rf "$TARGET_DIR/etc/xdg/weston/weston.ini.d/"

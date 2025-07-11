#!/bin/sh
#
# Modules init
#

start() {
	find /lib/modules/$(uname -r)/kernel/ -name "*.ko" \
		-exec modprobe --force {} \;
}

case "$1" in
	start)
		start
		;;
	*)
		echo "Usage: $0 start"
		exit 1
esac

exit $?

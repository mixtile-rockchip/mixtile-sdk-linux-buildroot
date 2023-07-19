################################################################################
#
# seatd
#
################################################################################

SEATD_VERSION = 0.7.0
SEATD_SOURCE = $(SEATD_VERSION).tar.gz
SEATD_SITE = https://git.sr.ht/~kennylevinsen/seatd/archive
SEATD_LICENSE = MIT
SEATD_LICENSE_FILES = LICENSE
SEATD_INSTALL_STAGING = YES

SEATD_CONF_OPTS += \
	-Dman-pages=disabled \
	-Dexamples=disabled \
	-Dwerror=false

ifeq ($(BR2_PACKAGE_SYSTEMD_LOGIND),y)
SEATD_CONF_OPTS += -Dlibseat-logind=systemd
SEATD_DEPENDENCIES += systemd
else
SEATD_CONF_OPTS += -Dlibseat-logind=disabled
endif

ifeq ($(BR2_PACKAGE_SEATD_BUILTIN),y)
SEATD_CONF_OPTS += -Dlibseat-builtin=enabled
else
SEATD_CONF_OPTS += -Dlibseat-builtin=disabled
endif

ifeq ($(BR2_PACKAGE_SEATD_DAEMON),y)
SEATD_CONF_OPTS += -Dlibseat-seatd=enabled -Dserver=enabled

define SEATD_USERS
	- - video -1 - - - - -
endef

define SEATD_INSTALL_INIT_SYSV
	$(INSTALL) -m 0755 -D $(SEATD_PKGDIR)/S40seatd \
		$(TARGET_DIR)/etc/init.d/S40seatd
endef

define SEATD_INSTALL_INIT_SYSTEMD
	$(INSTALL) -m 0644 -D $(@D)/contrib/systemd/seatd.service \
		$(TARGET_DIR)/usr/lib/systemd/system/seatd.service
endef

ifeq ($(BR2_PACKAGE_SEATD_DAEMON_VT_BOUND),)
define SEATD_INSTALL_TARGET_VT_ENV
	echo "export SEATD_VTBOUND=0" > \
		$(TARGET_DIR)/etc/profile.d/seatd.sh
endef
SEATD_POST_INSTALL_TARGET_HOOKS += SEATD_INSTALL_TARGET_VT_ENV
endif

else
SEATD_CONF_OPTS += -Dlibseat-seatd=disabled -Dserver=disabled
endif

$(eval $(meson-package))

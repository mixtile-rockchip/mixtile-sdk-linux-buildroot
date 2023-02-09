################################################################################
#
# rkscript
#
################################################################################

RKSCRIPT_SITE = $(TOPDIR)/../external/rkscript
RKSCRIPT_SITE_METHOD = local
RKSCRIPT_LICENSE = ROCKCHIP
RKSCRIPT_LICENSE_FILES = LICENSE

RKSCRIPT_ADD_TOOLCHAIN_DEPENDENCY=no

ifeq ($(BR2_PACKAGE_RKSCRIPT_USB),y)
RKSCRIPT_USB_CONFIG=$(BR2_PACKAGE_RKSCRIPT_USB_EXTRA_CONFIG)

ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_ADBD),y)
RKSCRIPT_USB_CONFIG += adb
endif
ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_MTP),y)
RKSCRIPT_USB_CONFIG += mtp
endif
ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_ACM),y)
RKSCRIPT_USB_CONFIG += acm
endif
ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_NTB),y)
RKSCRIPT_USB_CONFIG += ntb
endif
ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_UVC),y)
RKSCRIPT_USB_CONFIG += uvc
endif
ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_UAC1),y)
RKSCRIPT_USB_CONFIG += uac1
endif
ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_UAC2),y)
RKSCRIPT_USB_CONFIG += uac2
endif
ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_HID),y)
RKSCRIPT_USB_CONFIG += hid
endif
ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_RNDIS),y)
RKSCRIPT_USB_CONFIG += rndis
endif
ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_UMS),y)
RKSCRIPT_USB_CONFIG += ums
endif

define usb_env_fixup
	$(SED) "s#\($1=\).*#\1\"$(call qstrip,$2)\"#" \
		$(TARGET_DIR)/etc/profile.d/usbdevice.sh
endef

define RKSCRIPT_INSTALL_TARGET_USB_ENV
	$(INSTALL) -D -m 0644 $(RKSCRIPT_PKGDIR)/usbdevice.sh \
		$(TARGET_DIR)/etc/profile.d/usbdevice.sh
	$(call usb_env_fixup,USB_FUNCS,$(RKSCRIPT_USB_CONFIG))
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_USB_ENV

ifeq ($(BR2_PACKAGE_RKSCRIPT_USB_UMS),y)
define ums_env_fixup
	V=$(BR2_PACKAGE_RKSCRIPT_USB_$(1)); \
		if [ "$$V" = y ]; then V=1; fi; \
		if [ "$$V" ]; then $(call usb_env_fixup,$(1),$$V); fi
endef

RKSCRIPT_UMS_ENV = UMS_FILE UMS_SIZE UMS_FSTYPE UMS_MOUNT UMS_MOUNTPOINT UMS_RO
define RKSCRIPT_INSTALL_TARGET_USB_UMS_ENV
	$(foreach env,$(RKSCRIPT_UMS_ENV),$(call ums_env_fixup,$(env))$(sep))
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_USB_UMS_ENV
endif # UMS

define RKSCRIPT_INSTALL_TARGET_USB
	$(INSTALL) -m 0755 -D $(@D)/usbdevice $(TARGET_DIR)/usr/bin/
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_USB

ifeq ($(BR2_PACKAGE_HAS_UDEV),y)
define RKSCRIPT_INSTALL_TARGET_USB_UDEV_RULES
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/udev/rules.d/
	$(INSTALL) -m 0644 -D $(@D)/61-usbdevice.rules \
		$(TARGET_DIR)/lib/udev/rules.d/
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_USB_UDEV_RULES
endif

define RKSCRIPT_INSTALL_INIT_SYSV_USB
	$(INSTALL) -m 0755 -D $(@D)/S50usbdevice $(TARGET_DIR)/etc/init.d/
endef
RKSCRIPT_INSTALL_INIT_SYSV_HOOKS += RKSCRIPT_INSTALL_INIT_SYSV_USB

define RKSCRIPT_INSTALL_INIT_SYSTEMD_USB
	$(INSTALL) -D -m 644 $(@D)/usbdevice.service \
		$(TARGET_DIR)/usr/lib/systemd/system/
endef
RKSCRIPT_INSTALL_INIT_SYSTEMD_HOOKS += RKSCRIPT_INSTALL_INIT_SYSTEMD_USB
endif # USB

ifeq ($(BR2_PACKAGE_RKSCRIPT_IODOMAIN),y)
define RKSCRIPT_INSTALL_TARGET_IODOMAIN
	$(INSTALL) -m 0755 -D $(@D)/list-iodomain.sh $(TARGET_DIR)/usr/bin/
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_IODOMAIN

define RKSCRIPT_INSTALL_INIT_SYSV_IODOMAIN
	$(INSTALL) -m 0755 -D $(@D)/S98iodomain.sh $(TARGET_DIR)/etc/init.d/
endef
RKSCRIPT_INSTALL_INIT_SYSV_HOOKS += RKSCRIPT_INSTALL_INIT_SYSV_IODOMAIN
endif # IODOMAIN

ifeq ($(BR2_PACKAGE_RKSCRIPT_MOUNTALL),y)
define RKSCRIPT_INSTALL_TARGET_MOUNTALL
	$(INSTALL) -m 0755 -D $(@D)/disk-helper $(TARGET_DIR)/usr/bin/
	$(INSTALL) -m 0755 -D $(@D)/mount-helper $(TARGET_DIR)/usr/bin/
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_MOUNTALL

define RKSCRIPT_INSTALL_INIT_SYSV_MOUNTALL
	$(INSTALL) -m 0755 -D $(@D)/S21mountall.sh $(TARGET_DIR)/etc/init.d/
endef
RKSCRIPT_INSTALL_INIT_SYSV_HOOKS += RKSCRIPT_INSTALL_INIT_SYSV_MOUNTALL
endif # MOUNTALL

ifeq ($(BR2_PACKAGE_RKSCRIPT_RESIZEALL),y)
define RKSCRIPT_INSTALL_TARGET_RESIZEALL
	$(INSTALL) -m 0755 -D $(@D)/disk-helper $(TARGET_DIR)/usr/bin/
	$(INSTALL) -m 0755 -D $(@D)/resize-helper $(TARGET_DIR)/usr/bin/
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_RESIZEALL

define RKSCRIPT_INSTALL_INIT_SYSV_RESIZEALL
	$(INSTALL) -m 0755 -D $(@D)/S21resizeall.sh $(TARGET_DIR)/etc/init.d/
endef
RKSCRIPT_INSTALL_INIT_SYSV_HOOKS += RKSCRIPT_INSTALL_INIT_SYSV_RESIZEALL

define RKSCRIPT_INSTALL_INIT_SYSTEMD_RESIZEALL
	$(INSTALL) -D -m 644 $(@D)/resize-all.service \
		$(TARGET_DIR)/usr/lib/systemd/system/
endef
RKSCRIPT_INSTALL_INIT_SYSTEMD_HOOKS += RKSCRIPT_INSTALL_INIT_SYSTEMD_RESIZEALL
endif # RESIZEALL

ifeq ($(BR2_PACKAGE_RKSCRIPT_BOOTANIM),y)
define RKSCRIPT_INSTALL_TARGET_BOOTANIM
	$(INSTALL) -m 0755 -D $(@D)/bootanim $(TARGET_DIR)/usr/bin/
	$(SED) "s/^\(TIMEOUT=\).*/\1$(BR2_PACKAGE_RKSCRIPT_BOOTANIM_TIMEOUT)/" \
		$(TARGET_DIR)/usr/bin/bootanim

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc/bootanim.d/
	$(INSTALL) -m 0755 -D $(RKSCRIPT_PKGDIR)/gst-bootanim.sh \
		$(TARGET_DIR)/etc/bootanim.d/
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_BOOTANIM

define RKSCRIPT_INSTALL_INIT_SYSV_BOOTANIM
	$(INSTALL) -m 0755 -D $(@D)/S31bootanim.sh $(TARGET_DIR)/etc/init.d/
endef
RKSCRIPT_INSTALL_INIT_SYSV_HOOKS += RKSCRIPT_INSTALL_INIT_SYSV_BOOTANIM

define RKSCRIPT_INSTALL_INIT_SYSTEMD_BOOTANIM
	$(INSTALL) -D -m 644 $(@D)/bootanim.service \
		$(TARGET_DIR)/usr/lib/systemd/system/
endef
RKSCRIPT_INSTALL_INIT_SYSTEMD_HOOKS += RKSCRIPT_INSTALL_INIT_SYSTEMD_BOOTANIM
endif # BOOTANIM

ifneq ($(BR2_PACKAGE_RKSCRIPT_DEFAULT_PCM),"")
define RKSCRIPT_INSTALL_TARGET_PCM_HOOK
	$(SED) "s#\#PCM_ID#$(BR2_PACKAGE_RKSCRIPT_DEFAULT_PCM)#g" \
		$(@D)/asound.conf.in
	$(INSTALL) -m 0644 -D $(@D)/asound.conf.in $(TARGET_DIR)/etc/asound.conf
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_PCM_HOOK
endif # PCM

ifeq ($(BR2_PACKAGE_HAS_UDEV),y)
define RKSCRIPT_INSTALL_TARGET_UDEV_RULES
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/udev/rules.d/
	$(INSTALL) -m 0644 -D $(@D)/61-partition-init.rules \
		$(TARGET_DIR)/lib/udev/rules.d/
	$(INSTALL) -m 0644 -D $(@D)/88-rockchip-camera.rules \
		$(TARGET_DIR)/lib/udev/rules.d/
	$(INSTALL) -m 0644 -D $(@D)/99-rockchip-permissions.rules \
		$(TARGET_DIR)/lib/udev/rules.d/
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_UDEV_RULES
endif # UDEV

define RKSCRIPT_INSTALL_INIT_SYSV
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc/init.d/
	$(foreach hook,$(RKSCRIPT_INSTALL_INIT_SYSV_HOOKS),$(call $(hook))$(sep))
endef

define RKSCRIPT_INSTALL_INIT_SYSTEMD
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/systemd/system/
	$(foreach hook,$(RKSCRIPT_INSTALL_INIT_SYSTEMD_HOOKS),$(call $(hook))$(sep))
endef

$(eval $(generic-package))

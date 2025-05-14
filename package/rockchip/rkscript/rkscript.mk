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

ifeq ($(BR2_PACKAGE_RKSCRIPT_IODOMAIN_NOTICE),y)
define RKSCRIPT_INSTALL_TARGET_IODOMAIN_NOTICE
	$(INSTALL) -m 0755 -D $(@D)/list-iodomain.sh $(TARGET_DIR)/usr/bin/
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_IODOMAIN_NOTICE

define RKSCRIPT_INSTALL_INIT_SYSV_IODOMAIN_NOTICE
	$(INSTALL) -m 0755 -D $(@D)/S*iodomain.sh $(TARGET_DIR)/etc/init.d/
endef
RKSCRIPT_INSTALL_INIT_SYSV_HOOKS += RKSCRIPT_INSTALL_INIT_SYSV_IODOMAIN_NOTICE
endif # IODOMAIN_NOTICE

ifneq ($(BR2_PACKAGE_RKSCRIPT_DEFAULT_PCM),"")
define RKSCRIPT_INSTALL_TARGET_PCM_HOOK
	$(SED) "s#\#PCM_ID#$(BR2_PACKAGE_RKSCRIPT_DEFAULT_PCM)#g" \
		$(@D)/asound.conf.in
	$(INSTALL) -m 0644 -D $(@D)/asound.conf.in $(TARGET_DIR)/etc/asound.conf
endef
RKSCRIPT_POST_INSTALL_TARGET_HOOKS += RKSCRIPT_INSTALL_TARGET_PCM_HOOK
endif # PCM

define RKSCRIPT_INSTALL_INIT_SYSV
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc/init.d/
	$(foreach hook,$(RKSCRIPT_INSTALL_INIT_SYSV_HOOKS),$(call $(hook))$(sep))
endef

$(eval $(generic-package))

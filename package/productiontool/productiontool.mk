################################################################################
#
# ProductionTool
#
################################################################################

PRODUCTIONTOOL_VERSION = HEAD
PRODUCTIONTOOL_SITE = https://code.focalcrest.com/zaki/ProductionTool.git
PRODUCTIONTOOL_SITE_METHOD = git
PRODUCTIONTOOL_LICENSE = Proprietary
PRODUCTIONTOOL_SKIP_ARCH_CHECK = YES

define PRODUCTIONTOOL_BUILD_CMDS
	# nothing to build
endef

define PRODUCTIONTOOL_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/root/ProductionTool
	rsync -a \
		--exclude='.git' \
		--exclude='*.elf' \
		$(@D)/ \
		$(TARGET_DIR)/root/ProductionTool/
endef

$(eval $(generic-package))

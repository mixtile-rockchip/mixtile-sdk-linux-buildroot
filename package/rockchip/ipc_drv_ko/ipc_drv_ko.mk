################################################################################
#
# rockit project
#
################################################################################

IPC_DRV_KO_SITE = $(TOPDIR)/../external/ipc_drv_ko

IPC_DRV_KO_SITE_METHOD = local

IPC_DRV_KO_INSTALL_STAGING = YES

IPC_DRV_KO_CONF_OPTS += -DFOR_BUILDROOT=TRUE

$(eval $(cmake-package))

################################################################################
#
# wayland-cluster
#
################################################################################

WAYLAND_CLUSTER_VERSION = main
WAYLAND_CLUSTER_SITE = $(TOPDIR)/../app/wayland-cluster-app
WAYLAND_CLUSTER_SITE_METHOD = local

WAYLAND_CLUSTER_LICENSE = BSD3

WAYLAND_CLUSTER_DEPENDENCIES += cairo
WAYLAND_CLUSTER_DEPENDENCIES += fontconfig
WAYLAND_CLUSTER_DEPENDENCIES += libegl
WAYLAND_CLUSTER_DEPENDENCIES += stb
WAYLAND_CLUSTER_DEPENDENCIES += wayland
WAYLAND_CLUSTER_DEPENDENCIES += wayland-protocols

$(eval $(cmake-package))

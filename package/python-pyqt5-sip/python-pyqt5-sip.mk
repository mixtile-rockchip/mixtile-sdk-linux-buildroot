################################################################################
#
# python-SIP-QT5
#
################################################################################

PYTHON_PYQT5_SIP_VERSION = 12.12.1
PYTHON_PYQT5_SIP_SITE = https://files.pythonhosted.org/packages/c1/61/4055e7a0f36339964956ff415e36f4abf82561904cc49c021da32949fc55
PYTHON_PYQT5_SIP_SOURCE = PyQt5_sip-$(PYTHON_PYQT5_SIP_VERSION).tar.gz
PYTHON_PYQT5_SIP_LICENSE = MIT
PYTHON_PYQT5_SIP_LICENSE_FILES = LICENSE
PYTHON_PYQT5_SIP_SETUP_TYPE = setuptools
PYTHON_PYQT5_SIP_DEPENDENCIES += python-sip

$(eval $(python-package))

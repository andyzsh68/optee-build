################################################################################
#
# Xen with patches to support OP-TEE
#
################################################################################

XEN_OPTEE_VERSION = optee-br
XEN_OPTEE_SITE = https://github.com/andyzsh68/xen.git
XEN_OPTEE_SITE_METHOD=git
XEN_OPTEE_LICENSE = GPL-2.0
XEN_OPTEE_LICENSE_FILES = COPYING
XEN_OPTEE_DEPENDENCIES = host-acpica host-python

# Calculate XEN_OPTEE_ARCH
ifeq ($(ARCH),aarch64)
XEN_ARCH = arm64
else ifeq ($(ARCH),arm)
XEN_ARCH = arm32
endif

XEN_OPTEE_CONF_OPTS = --disable-ocamltools

XEN_OPTEE_CONF_ENV = PYTHON=$(HOST_DIR)/bin/python2
XEN_OPTEE_MAKE_ENV = \
	XEN_TARGET_ARCH=$(XEN_ARCH) \
	CROSS_COMPILE=$(TARGET_CROSS) \
	HOST_EXTRACFLAGS="-Wno-error" \
	XEN_CONFIG_EXPERT=y \
	$(TARGET_CONFIGURE_OPTS)

ifeq ($(BR2_PACKAGE_XEN_OPTEE_HYPERVISOR),y)
XEN_OPTEE_MAKE_OPTS += dist-xen
XEN_OPTEE_INSTALL_IMAGES = YES
define XEN_OPTEE_INSTALL_IMAGES_CMDS
	cp $(@D)/xen/xen $(BINARIES_DIR)
endef
else
XEN_OPTEE_CONF_OPTS += --disable-xen
endif

ifeq ($(BR2_PACKAGE_XEN_OPTEE_TOOLS),y)
XEN_OPTEE_DEPENDENCIES += dtc libaio libglib2 ncurses openssl pixman util-linux yajl
ifeq ($(BR2_PACKAGE_ARGP_STANDALONE),y)
XEN_OPTEE_DEPENDENCIES += argp-standalone
endif
XEN_OPTEE_INSTALL_TARGET_OPTS += DESTDIR=$(TARGET_DIR) install-tools
XEN_OPTEE_MAKE_OPTS += dist-tools
XEN_LORC_OPTEE_MAKE_OPTS += "XEN_CONFIG_EXPERT=y" "CONFIG_TEE=y" "CONFIG_OPTEE=y"
XEN_LORC_OPTEE_CONF_OPTS += "XEN_CONFIG_EXPERT=y" "CONFIG_TEE=y" "CONFIG_OPTEE=y"
XEN_LORC_OPTEE_MAKE_OPTS += "XEN_CONFIG_EXPERT=y" "TEE=y" "OPTEE=y"
XEN_LORC_OPTEE_CONF_OPTS += "XEN_CONFIG_EXPERT=y" "TEE=y" "OPTEE=y"
XEN_OPTEE_CONF_OPTS += --with-extra-qemuu-configure-args="--disable-sdl"

define XEN_OPTEE_INSTALL_INIT_SYSV
	mv $(TARGET_DIR)/etc/init.d/xencommons $(TARGET_DIR)/etc/init.d/S50xencommons
	mv $(TARGET_DIR)/etc/init.d/xen-watchdog $(TARGET_DIR)/etc/init.d/S50xen-watchdog
	mv $(TARGET_DIR)/etc/init.d/xendomains $(TARGET_DIR)/etc/init.d/S60xendomains
endef
else
XEN_OPTEE_INSTALL_TARGET = NO
XEN_OPTEE_CONF_OPTS += --disable-tools
endif

$(eval $(autotools-package))

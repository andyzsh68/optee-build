################################################################################
#
# Xen with patches to support OP-TEE
#
################################################################################
XEN_LOCAL_VERSION = 4.13
XEN_LOCAL_SOURCE = local
XEN_LOCAL_SITE = $(BR2_PACKAGE_XEN_LOCAL_SITE)
XEN_LOCAL_SITE_METHOD = local
#XEN_LOCAL_INSTALL_STAGING = YES
#XEN_SITE = https://github.com/andyzsh68/xen.git
#XEN_SITE_METHOD=git
#XEN_LICENSE = GPL-2.0
#XEN_LICENSE_FILES = COPYING
XEN_LOCAL_DEPENDENCIES = host-acpica host-python

# need this to sync local code, useless, just changing build dir from xen_local_1.0 to xen_local_custom
#XEN_LOCAL_OVERRIDE_SRCDIR = $(BR2_PACKAGE_XEN_LOCAL_SITE)

# Calculate XEN_ARCH
ifeq ($(ARCH),aarch64)
XEN_ARCH = arm64
else ifeq ($(ARCH),arm)
XEN_ARCH = arm32
endif

#XEN_LOCAL_AUTORECONF = YES

XEN_LOCAL_CONF_OPTS = --disable-ocamltools

XEN_LOCAL_CONF_ENV = PYTHON=$(HOST_DIR)/bin/python2
XEN_LOCAL_MAKE_ENV = \
	XEN_TARGET_ARCH=$(XEN_ARCH) \
	CROSS_COMPILE=$(TARGET_CROSS) \
	HOST_EXTRACFLAGS="-Wno-error" \
	XEN_CONFIG_EXPERT=y \
	$(TARGET_CONFIGURE_OPTS)

ifeq ($(BR2_PACKAGE_XEN_LOCAL_HYPERVISOR),y)
XEN_LOCAL_MAKE_OPTS += dist-xen
XEN_LOCAL_INSTALL_IMAGES = YES
define XEN_LOCAL_INSTALL_IMAGES_CMDS
	cp $(@D)/xen/xen $(BINARIES_DIR)
endef
else
XEN_LOCAL_CONF_OPTS += --disable-xen
endif

ifeq ($(BR2_PACKAGE_XEN_LOCAL_TOOLS),y)
XEN_LOCAL_DEPENDENCIES += dtc libaio libglib2 ncurses openssl pixman util-linux yajl
ifeq ($(BR2_PACKAGE_ARGP_STANDALONE),y)
XEN_LOCAL_DEPENDENCIES += argp-standalone
endif
XEN_LOCAL_INSTALL_TARGET_OPTS += DESTDIR=$(TARGET_DIR) install-tools
XEN_LOCAL_MAKE_OPTS += dist-tools

XEN_LOCAL_CONF_OPTS += --with-extra-qemuu-configure-args="--disable-sdl"

define XEN_LOCAL_INSTALL_INIT_SYSV
	mv $(TARGET_DIR)/etc/init.d/xencommons $(TARGET_DIR)/etc/init.d/S50xencommons
	mv $(TARGET_DIR)/etc/init.d/xen-watchdog $(TARGET_DIR)/etc/init.d/S50xen-watchdog
	mv $(TARGET_DIR)/etc/init.d/xendomains $(TARGET_DIR)/etc/init.d/S60xendomains
endef

else
XEN_LOCAL_INSTALL_TARGET = NO
XEN_LOCAL_CONF_OPTS += --disable-tools
endif

define XEN_LOCAL_POST_INSTALL_IMAGES_FIXUP
	rm $(@D)/.stamp_rsynced
endef

#XEN_LOCAL_POST_INSTALL_IMAGES_HOOKS += XEN_LOCAL_POST_INSTALL_IMAGES_FIXUP

define XEN_LOCAL_PRE_RSYNC_FIXUP
	rm -rf $(@D)/
endef

#XEN_LOCAL_PRE_RSYNC_HOOKS += XEN_LOCAL_PRE_RSYNC_FIXUP

$(eval $(autotools-package))


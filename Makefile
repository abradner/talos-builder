PKG_VERSION := release-1.13
PKG_COMMIT := 969f61c
TALOS_VERSION := v1.13.2
SBCOVERLAY_VERSION := v0.2.0

PUSH ?= true
REGISTRY ?= ghcr.io
REGISTRY_USERNAME ?= talos-rpi5
TAG ?= $(shell git describe --tags --exact-match)

SED ?= sed
ASSET_TYPE ?= rpi_5
CONFIG_TXT ?= dtparam=i2c_arm=on

EXTENSIONS ?=
EXTENSION_ARGS := $(foreach ext,$(EXTENSIONS),--system-extension-image $(ext))

EXTRA_KERNEL_ARGS ?=
EXTRA_KERNEL := $(foreach arg,$(EXTRA_KERNEL_ARGS),--extra-kernel-arg $(arg))

PKG_REPOSITORY := https://github.com/siderolabs/pkgs.git
TALOS_REPOSITORY := https://github.com/siderolabs/talos.git
SBCOVERLAY_REPOSITORY := https://github.com/siderolabs/sbc-raspberrypi

CHECKOUTS_DIRECTORY := $(PWD)/checkouts
PATCHES_DIRECTORY := $(PWD)/patches

PKGS_TAG ?= $(or ${TAG}, $(shell cd $(CHECKOUTS_DIRECTORY)/pkgs && git describe --tag --always --dirty --match v[0-9]\*))
TALOS_TAG ?= $(or ${TAG}, $(shell cd $(CHECKOUTS_DIRECTORY)/talos && git describe --tag --always --dirty --match v[0-9]\*))
SBCOVERLAY_TAG ?= $(shell cd $(CHECKOUTS_DIRECTORY)/sbc-raspberrypi && git describe --tag --always --dirty --match v[0-9]\*)

#
# Help
#
.PHONY: help
help:
	@echo "checkouts        : Clone repositories required for the build"
	@echo "patches          : Apply all patches for Raspberry Pi 5"
	@echo "kernel           : Build kernel"
	@echo "overlay          : Build Raspberry Pi 5 overlay"
	@echo "imager           : Build imager docker image"
	@echo "installer-base   : Build installer-base docker image"
	@echo "initramfs-kernel : Build kernel and initramfs"
	@echo "installer        : Build installer"
	@echo "image            : Build disk image for Raspberry Pi 5"
	@echo "pi5              : Full build pipeline for Raspberry Pi 5"
	@echo "clean            : Clean up any remains"

#
# Checkouts
#
.PHONY: checkouts checkouts-clean
checkouts:
	git clone -c advice.detachedHead=false --single-branch --branch "$(PKG_VERSION)" "$(PKG_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/pkgs"
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && git reset --hard "$(PKG_COMMIT)"
	git clone -c advice.detachedHead=false --single-branch --branch "$(TALOS_VERSION)" "$(TALOS_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/talos"
	git clone -c advice.detachedHead=false --single-branch --branch "$(SBCOVERLAY_VERSION)" "$(SBCOVERLAY_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi"

checkouts-clean:
	rm -rf "$(CHECKOUTS_DIRECTORY)/pkgs"
	rm -rf "$(CHECKOUTS_DIRECTORY)/talos"
	rm -rf "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi"

#
# Patches
#
.PHONY: patches-pkgs patches-talos patches-sbc-raspberrypi patches
patches-pkgs:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/pkgs/0001-Patched-for-Raspberry-Pi-5.patch" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/pkgs/0002-Support-alternative-sed-interpreter.patch"

patches-talos:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/talos/0001-Patched-for-Raspberry-Pi-5.patch" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/talos/0002-Makefile.patch"

patches-sbc-raspberrypi:
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/sbc-raspberrypi/0001-Patched-for-Raspberry-Pi-5.patch"

patches-linux:
	# Remove patches targeting mainline kernel which are N/A in this vendor kernel
	rm -f "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches/0001-net-macb-flush-PCIe-posted-write-after-TSTART-doorbe.patch"
	rm -f "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches/0002-net-macb-re-check-ISR-after-IER-re-enable-in-macb_tx.patch"
	rm -f "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches/0002-net-macb-insert-PCIe-read-barrier-before-TX-completi.patch"
	rm -f "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches/0003-net-macb-add-TX-stall-watchdog-as-defence-in-depth-s.patch"
	rm -f "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches/0003-net-macb-add-TX-stall-watchdog-to-recover-from-lost-.patch"
	@if [ -d "$(PATCHES_DIRECTORY)/linux" ] && ls "$(PATCHES_DIRECTORY)/linux"/*.patch >/dev/null 2>&1; then \
		mkdir -p "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches" && \
		cp -v "$(PATCHES_DIRECTORY)/linux"/*.patch "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches/"; \
	else \
		echo "No local kernel patches in $(PATCHES_DIRECTORY)/linux, skipping"; \
	fi

patches: patches-pkgs patches-talos patches-sbc-raspberrypi patches-linux

.PHONY: kernel
kernel:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PLATFORM=linux/arm64 \
			kernel

.PHONY: overlay
overlay:
	@echo SBCOVERLAY_TAG = $(SBCOVERLAY_TAG)
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) IMAGE_TAG=$(SBCOVERLAY_TAG) PUSH=$(PUSH) \
			PKGS_PREFIX=$(REGISTRY)/$(REGISTRY_USERNAME) PKGS=$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			sbc-raspberrypi

.PHONY: imager
imager:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			TAG=${TALOS_TAG} REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 SED=$(SED) \
			imager

.PHONY: installer-base
installer-base:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			TAG=${TALOS_TAG} REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 SED=$(SED) \
			installer-base

.PHONY: initramfs-kernel
initramfs-kernel:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			TAG=${TALOS_TAG} REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 SED=$(SED) \
			initramfs kernel

.PHONY: installer
installer:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		docker \
			run --rm -t -v ./_out:/out -v /dev:/dev --privileged $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) \
			installer \
			--arch arm64 \
			--base-installer-image="$(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_TAG)" \
			--overlay-name="rpi_5" \
			--overlay-image="$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_TAG)" \
			--overlay-option="configTxtAppend=$$CONFIG_TXT" \
			$(EXTENSION_ARGS) \
			$(EXTRA_KERNEL)
		crane push \
			./checkouts/talos/_out/installer-arm64.tar \
			${REGISTRY}/${REGISTRY_USERNAME}/installer:${TALOS_TAG}-arm64-extensions

.PHONY: image
image:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		docker \
			run --rm -t -v ./_out:/out -v /dev:/dev --privileged $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) \
			$(ASSET_TYPE) \
			--arch arm64 \
			--base-installer-image="$(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_TAG)" \
			--overlay-name="rpi_5" \
			--overlay-image="$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_TAG)" \
			--overlay-option="configTxtAppend=$$CONFIG_TXT" \
			$(EXTENSION_ARGS) \
			$(EXTRA_KERNEL)

.PHONY: pi5
pi5: checkouts-clean checkouts patches kernel initramfs-kernel installer-base imager overlay installer image

.PHONY: clean
clean: checkouts-clean

#
# Upstream build: official Talos imager + official sbc-raspberrypi overlay,
# no kernel or overlay patches. The only customisation is the kernel
# arguments. Every input is pinned by digest. See docs/cm5-lite-upstream.md.
#
UPSTREAM_IMAGER ?= ghcr.io/siderolabs/imager:v1.14.4@sha256:91d453a7cf57d499fe7fe7923e1e381b6e1535136367246d190e38486c11651d
UPSTREAM_OVERLAY ?= ghcr.io/siderolabs/sbc-raspberrypi:v0.2.2@sha256:af82d9f97241fb66c5b660b03e9154fd54ba4560b58ed3b53765bb930d564167
# sdhci.debug_quirks2=4 is SDHCI_QUIRK2_NO_1_8_V: no UHS-I, so the SD card
# runs 3.3 V High Speed and the CM5 Lite never attempts the 1.8 V switch
# that fails on some carriers.
UPSTREAM_KERNEL_ARGS ?= sdhci.debug_quirks2=4
UPSTREAM_OUT ?= $(PWD)/_out
UPSTREAM_IMAGER_ARGS = --arch arm64 --overlay-name rpi_5 --overlay-image $(UPSTREAM_OVERLAY) \
	$(foreach arg,$(UPSTREAM_KERNEL_ARGS),--extra-kernel-arg $(arg))

.PHONY: upstream upstream-metal upstream-installer
upstream: upstream-metal upstream-installer

upstream-metal:
	mkdir -p "$(UPSTREAM_OUT)"
	docker run --rm -v "$(UPSTREAM_OUT)":/out -v /dev:/dev --privileged $(UPSTREAM_IMAGER) metal $(UPSTREAM_IMAGER_ARGS)
	zstd -d --rm -f "$(UPSTREAM_OUT)/metal-arm64.raw.zst" -o "$(UPSTREAM_OUT)/metal-arm64-rpi5.raw"
	xz -T0 -f "$(UPSTREAM_OUT)/metal-arm64-rpi5.raw"

upstream-installer:
	mkdir -p "$(UPSTREAM_OUT)"
	docker run --rm -v "$(UPSTREAM_OUT)":/out -v /dev:/dev --privileged $(UPSTREAM_IMAGER) installer $(UPSTREAM_IMAGER_ARGS)

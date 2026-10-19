# Raspberry Pi 5 Talos Builder

> **CM5 Lite, SD boot: use the upstream build.** Tags `v*.*.*-cm5l.*` build official Talos with the official `sbc-raspberrypi` overlay and no patches. Every input is pinned by digest, and the only customisation is one kernel argument, which keeps the SD card out of UHS-I. These are this fork's maintained CM5 Lite images. Why, how to bump, and test results: [docs/cm5-lite-upstream.md](docs/cm5-lite-upstream.md). The vendor-kernel pipeline described below is kept for reference.

This repository builds custom Talos Linux images for the **Raspberry Pi 5**. It patches the Kernel and Talos build process to use the Linux Kernel source provided by [raspberrypi/linux](https://github.com/raspberrypi/linux).

## Tested on

So far, this release has been verified on:

| ✅ Hardware                                                |
|------------------------------------------------------------|
| Raspberry Pi Compute Module 5 on Compute Module 5 IO Board |
| Raspberry Pi Compute Module 5 Lite on [DeskPi Super6C](https://wiki.deskpi.com/super6c/) |
| Raspberry Pi 5b with [RS-P11 for RS-P22 RPi5](https://wiki.52pi.com/index.php?title=EP-0234) |

## What's not working?

* Booting from USB: USB is only available once LINUX has booted up but not in U-Boot.

## How to use?

Each release contains disk images and installer images for the Raspberry Pi 5 platforms.

### Examples

Initial:

```bash
# Raspberry Pi 5 / CM5
xz -d metal-arm64-rpi5.raw.xz
dd if=metal-arm64-rpi5.raw of=<disk> bs=4M status=progress
```

Upgrade:

```bash
# Raspberry Pi 5 / CM5
talosctl upgrade \
  --nodes <node IP> \
  --image ghcr.io/talos-rpi5/installer:<version>-rpi5
```

## Building

### Using GitHub Actions

The CI workflow builds and publishes images automatically. It is triggered when you push a version tag:

- **Push a tag** matching `v*.*.*` — this builds the Raspberry Pi 5 image and creates a GitHub Release:
  ```bash
  git tag v1.12.6
  git push origin v1.12.6
  ```

### Local build

If you'd like to make modifications, it is possible to create your own build.

```bash
# Full pipeline for Raspberry Pi 5
make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> pi5
```

Or step by step:

```bash
# Clone dependencies and apply patches
make checkouts patches

# Build the Linux Kernel (can take a while)
make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> kernel

# Build the overlay (Pi5 only — Pi4 uses the stock siderolabs overlay)
make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> overlay

# Build the installer and disk image
make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> installer
```

### Extensions support

Talos [system extensions](https://www.talos.dev/latest/talos-guides/configuration/system-extensions/) can be baked into the installer image at build time.

**Makefile variables:**

```makefile
EXTENSIONS ?=
EXTENSION_ARGS = $(foreach ext,$(EXTENSIONS),--system-extension-image $(ext))
```

`EXTENSIONS` is a space-separated list of `image:tag@sha256:digest` references passed as a make variable at build time — no Makefile edits needed. Internally, the Makefile expands each entry into a `--system-extension-image` flag and passes them all to the Talos imager.

**Adding extensions to the CI build:**

Just add a new `EXTENSION_*` env var at the top of `.github/workflows/build.yaml` — the digest resolution step automatically loops through all vars matching that prefix:

```yaml
env:
  EXTENSION_ISCSI_IMAGE: ghcr.io/siderolabs/iscsi-tools:v0.2.0
  EXTENSION_UTIL_LINUX_IMAGE: ghcr.io/siderolabs/util-linux-tools:2.41.2
  EXTENSION_MY_IMAGE: ghcr.io/siderolabs/my-extension:v1.0.0   # ← just add this
```

The workflow resolves the digest for each at build time and assembles the full `EXTENSIONS` string automatically.

**Adding extensions for a local build:**

```bash
# Resolve the digest first
DIGEST=$(crane digest ghcr.io/siderolabs/foo-extension:v1.0.0)

make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> \
  EXTENSIONS="ghcr.io/siderolabs/foo-extension:v1.0.0@${DIGEST}" \
  installer
```

Pass multiple extensions as a space-separated string inside the quotes.

## License

See [LICENSE](LICENSE).

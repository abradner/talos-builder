# Upstream Talos on CM5 Lite (SD boot)

The `upstream-cm5l` workflow (`.github/workflows/upstream.yaml`, `make upstream`) builds Talos for Raspberry Pi CM5 Lite nodes that boot from SD. It uses official inputs only:

| Input | Pin (in `Makefile`) |
|---|---|
| Talos imager | `ghcr.io/siderolabs/imager:v1.14.4@sha256:91d453a7…651d` |
| Board overlay | `ghcr.io/siderolabs/sbc-raspberrypi:v0.2.2@sha256:af82d9f9…4167` (`rpi_5`) |
| Kernel | the official Talos kernel inside the imager (6.18.57 for v1.14.4) |
| Extensions | none |
| Customisation | one kernel argument: `sdhci.debug_quirks2=4` |

It carries no kernel or overlay patches. The vendor-kernel pipeline (`build.yaml`, `make pi5`) is unchanged and still builds on `v*.*.*` tags. `v*.*.*-cm5l.*` tags go to this workflow instead.

## Why the kernel argument

On some CM5 Lite carriers, stock Talos 1.14.1 and 1.14.2 from Image Factory lose the SD card. The card negotiates UHS-I SDR104, the 1.8 V signal-voltage switch can't be verified, and the kernel loops on `error -84` / `error -110` / `cannot verify signal voltage switch` until it gives up. Then `mmcblk0` never appears, and a machine config that installs to it stalls. The same software on a different carrier, with the same cards, enumerated cleanly at SDR104.

What was ruled out:
- **The device tree is not the cause.** The overlay's `bcm2712-rpi-cm5l-*.dtb` has the CM5 Lite's switchable SD I/O regulator (`regulator-gpio` on `gio_aon` line 3, 1.8 V/3.3 V) and `sd-uhs-sdr50/ddr50/sdr104` on `sdio1`. A vendor-kernel build that runs on CM5 Lites has the same nodes; it differs only by `supports-cqe`. siderolabs/sbc-raspberrypi#98 changes the shared `cm5.dtsi`, which is not the file a CM5 Lite loads.
- **The kernel driver differs.** The Pi Foundation kernel's `sdhci-brcmstb` has its own BCM2712 `set_clock`, which switches the controller's SD/eMMC pin select per bus timing. Mainline uses the generic `sdhci_set_clock`. That difference is a plausible cause but unproven.

`sdhci.debug_quirks2=4` sets `SDHCI_QUIRK2_NO_1_8_V`. It is the same flag the `no-1-8-v` device-tree property sets: `sdhci_setup_host()` strips SDR50/SDR104/DDR50 and the 1.8 V eMMC modes. The card then runs 3.3 V High Speed (50 MHz, about 20 MB/s) and never attempts the voltage switch. These nodes keep `/var` (EPHEMERAL) on NVMe and use the SD for boot only, so the lower speed costs nothing that matters.

Notes on the mechanism:
- `debug_quirks2` **replaces** the host's `quirks2` when the capabilities are read. `sdhci-brcmstb` ORs in `SDHCI_QUIRK2_PRESET_VALUE_BROKEN` afterwards, so nothing it needs is lost.
- The argument applies to every SDHCI host. On a CM5 Lite the other one is the Wi-Fi SDIO bus, which doesn't use 1.8 V signalling.
- The imager bakes the argument into the installer's command line, so `talosctl upgrade -i <this installer>` keeps it. An upgrade with any other installer drops it.

## Test results

See "Boot test" in the release notes of each tag, and the summary below.

| Date | Image | Carrier | Card | Result |
|---|---|---|---|---|
| 2026-10-19 | Factory schematic `03fea4ec…` (same inputs as this pipeline) v1.14.4 | the carrier where Factory 1.14.1/1.14.2 lose SD | 64 GB SDXC (SPCC) | *in progress* |

## Bumping Talos

1. Find the new imager digest: `crane digest ghcr.io/siderolabs/imager:vX.Y.Z`.
2. Check Image Factory's overlay for that version: `curl -s https://factory.talos.dev/version/vX.Y.Z/overlays/official`, entry `rpi_5`. Use the same overlay version and digest.
3. Update `UPSTREAM_IMAGER` and `UPSTREAM_OVERLAY` in the `Makefile`, then build locally with `make upstream UPSTREAM_OUT=/tmp/out`.
4. Merge, then tag `vX.Y.Z-cm5l.1`. The workflow refuses to build if the tag's Talos version doesn't match the imager pin.
5. Boot-test the new image on the problem carrier before rolling it out: SD present (`talosctl get disks`), no `error -84`/`-110` in `dmesg`, `end0` up, across several reboots and a power cycle.

If upstream ever fixes the voltage switch, try dropping the argument (`UPSTREAM_KERNEL_ARGS=`) and re-run the boot test.

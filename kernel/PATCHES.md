# Local kernel patches

`prepare()` applies them in this order, after every t2linux patch: the five yuters patches, then `extra-01` to `extra-13`. The order comes from PKGBUILD `source=()`, not from a glob.

Kernel patches are GPL-2.0, like the kernel. The `From:`, `Subject:` and `Signed-off-by:` headers are kept as upstream wrote them. 05 and 06 have no `From:` line upstream; both come from the KaiT2en tree (André Eikmeyer, deqrocks).

## Base

| Piece | Pin |
| --- | --- |
| Kernel | 7.2.15 (last 7.2, EOL) + Arch `v7.2.15-arch1` |
| t2linux | [`e167207`](https://github.com/t2linux/linux-t2-patches/tree/e16720782ee30fac38486b6c58d32443899c136a) (2026-10-16). Last commit before the 7.3 move; its `version` file still says `KVER=7.2.10` |
| Packaging + config | [linux-t2-arch `b68c1c2`](https://github.com/NoaHimesaka1873/linux-t2-arch/commit/b68c1c2) (`v7.2.14.arch1-1`), bumped to 7.2.15 by hand |

## yuters e77b03f

From [yuters/mbp161-hybrid-graphics `e77b03f`](https://github.com/yuters/mbp161-hybrid-graphics/tree/e77b03fe0902216a7544208f2988b4cd391423a1/kernel). 0002–0005 are byte-identical.

**0001 is refreshed for t2linux `e167207`.** t2linux fixed a typo in its own `2009-apple-gmux-allow-switching-to-igpu-at-probe.patch`: `MODULE_PARM_DESC(force_idg, …)` became `force_igd`. 0001 deletes that line, so its `-` line now says `force_igd`. Nothing else changed.

## extra-01 to extra-07: KaiT2en

From [kaiT2en/KaiT2en-Fedora `8de9546`](https://github.com/kaiT2en/KaiT2en-Fedora/tree/8de95468f08c6db37924bcb8f9adc12c769add71/patches/runtime), under `patches/runtime/`.

| File | Upstream | What it does | State |
| --- | --- | --- | --- |
| `extra-01` | `wireless/0001-wifi-brcmfmac-disable-TX-beamforming-on-BCM4364.patch` | No TX beamforming on BCM4364 | identical |
| `extra-02` | `wireless/0002-Bluetooth-btbcm-raise-ACL-priority-on-Apple-Broadcom-controllers.patch` | High ACL priority on Broadcom Bluetooth links: stops A2DP dropouts while 2.4 GHz Wi-Fi is busy. `BT_HCIBCM4377` now selects `BT_BCM` | identical |
| `extra-03` | `wireless/0003-wifi-brcmfmac-use-a-200-ms-power-save-timeout-by-default.patch` | 200 ms Wi-Fi power-save timeout instead of 2 s (about 2 W less at idle, measured on a 15,1) | identical |
| `extra-04` | `wireless/0014-wifi-brcmfmac-keep-ARP-and-ND-offload-off-on-the-BCM4364-while-awake.patch` | Fixes IPv6 capped near 55 Mbit/s on BCM4364 (firmware ND offload). See `docs/ab-tests-audio-wifi.md` | identical |
| `extra-05` | `i915/0001-drm-dp-allow-psr-on-apple-panels.patch` | Drops the blanket `NO_PSR` quirk on Apple eDP panels | identical |
| `extra-06` | `i915/0002-drm-i915-psr-apple-tcon-handshake.patch` | Apple TCON PSR handshake | identical |
| `extra-07` | `i915/0003-drm-i915-backlight-restore-the-gmux-brightness-on-T2-MacBook-Pros.patch` | Restores gmux brightness (DMI list includes MacBookPro16,1) | **rebased** |

**Rebase of `extra-07`.** The `intel_quirks.h` hunk now ends its context on `QUIRK_DDI_A_FORCE_4_LANES`, which t2linux `2008-i915-4-lane-quirk-for-mbp15-1.patch` adds just before the new entry. It keeps three context lines on each side, so it applies with `--fuzz=0`. The code is unchanged.

**PSR (05, 06) is new on this machine.** Upstream tested it on a MacBookPro16,2, not on the 16,1. If the panel flickers or freezes, boot once with `i915.enable_psr=0`. That disables PSR without a rebuild.

## extra-08 to extra-13: klizas

From [klizas/t2-kernel-patches `5181c93`](https://github.com/klizas/t2-kernel-patches/tree/5181c93904deb02ddfea64e96608b7ebffb8ca2a).

| File | Upstream | What it does | State |
| --- | --- | --- | --- |
| `extra-08` | `0001-touchbar-suspend-resume.patch` | Touch Bar keyboard (`hid-appletb-kbd`) survives suspend/resume | **rebased** |
| `extra-09` | `0001-appletbdrm-zlp-pad.patch` | Pads Touch Bar DRM requests that are an exact multiple of 512 bytes (device stall) | identical |
| `extra-10` | `0001-appletbdrm-kzalloc-request.patch` | Zeroed framebuffer request | identical |
| `extra-11` | `0001-appletbdrm-reset-free-old-state.patch` | Frees the old plane state in reset | identical |
| `extra-12` | `0001-brcmfmac-suspend-fix.patch` | Suspend no longer fails when Wi-Fi firmware stops responding (v3) | identical |
| `extra-13` | `0002-brcmfmac-resume-liveness-probe.patch` | Detects firmware that died across suspend and reloads it | identical |

**Rebase of `extra-08`.** `system_dfl_wq` became `system_wq` (twice) to match what 7.2.15 `hid-appletb-kbd.c` uses. The logic is unchanged.

## Overlap with t2linux, yuters and Omarchy 4.5

All 18 local patches apply on top of every t2linux patch. A hunk that t2linux already carried would be rejected as "previously applied", so none of them duplicates t2linux. yuters and the extras touch disjoint files.

Four t2linux patches touch the same files. Each extra sits on top of one and does something else:

| t2linux | Extra | Relation |
| --- | --- | --- |
| `2008` i915 4-lane quirk (MBP15,1) | `extra-07` | Adds a separate quirk next to it |
| `5001` hid-appletb-kbd: double-press fn switches layer | `extra-08` | Suspend/resume in the same driver |
| `5002` appletbdrm suspend/resume | `extra-09`–`11` | Three unrelated appletbdrm bugs |
| `9003` brcmfmac D3 timeout (continues suspend on a missing ACK) | `extra-12` | v3 builds on 9003: it flags that path and reloads the firmware on resume |

What Omarchy 4.5 sets, and what that means for each patch:

| Omarchy 4.5 | Patches | Effect |
| --- | --- | --- |
| `wifi.powersave = 2` (NetworkManager, power save off) | `extra-03` | Inert. The 200 ms timeout only matters with power save on |
| `brcmfmac feature_disable=0x82000` (same file and line as this toolbox) | `01`, `04`, `12`, `13` | Independent firmware features. No conflict |
| Touch Bar on the in-kernel Boot Camp mode. A migration removes `tiny-dfr` | `08` active. `09`–`11` dormant | `08` fixes the blank Touch Bar after resume in exactly that mode. appletbdrm only binds in USB config 2, which this toolbox does not use (C7) |
| Brightness goes through `gmux_backlight` on dual-GPU Macs | `extra-07` | Puts back the gmux level that i915 resets to 80 % after lock or resume |
| Loads `hci_bcm4377` | `extra-02` | The 16,1's BCM4364 Bluetooth is on UART (`hci_bcm`). The patch covers both drivers |
| Nothing for PSR | `05`, `06` | New on the 16,1. Fallback `i915.enable_psr=0` |

`extra-04` changes only the Wi-Fi interface. The T2 NCM link that Touch ID uses keeps its IPv6.

Two klizas patches are deliberately left out:

- `xhci-pci-t2-titan-ridge-no-runtime-pm` duplicates yuters `0005` and the `72-mbp16-1-titan-ridge` udev rule.
- `x86-resume-cached-cpu-bringup` only matters for S3. This machine uses s2idle.

**Never combine with KaiT2en's Arch packages** (arch-mact2 tag `kait2en`). Their `kait2en-wireless-runtime-pm-t2` package ships the same Wi-Fi patches as modules built for `linux-t2` 7.2.11. The DKMS packages also build against `linux-t2-mbp161-headers`:

- `t2gmux-dkms` replaces `apple-gmux`, which yuters `0001` and `extra-07` rely on.
- `t2touchbar-dkms` replaces `hid-appletb-kbd`, which `extra-08` patches.
- `t2bce-dkms` replaces the in-tree t2bce.

That stack is palier 2 (stock `linux-t2` without these extras), never on top of this kernel.

## Refreshing

If a patch rejects on a new base, stop. Refresh that one patch from its upstream, at a pinned commit. Note the change here and keep its headers. Never take yuters `main`.

Do not file issues or PRs at KaiT2en on the user's behalf. That project rejects AI-generated contributions.

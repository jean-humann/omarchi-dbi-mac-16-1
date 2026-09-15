# Dual-boot Omarchy on MacBookPro16,1 (A2141)

Keep **macOS**. Install **Omarchy 4.0.3** into **unallocated** space on a 16-inch 2019 Intel (`MacBookPro16,1` / A2141). Intel lid + idle AMD, USB-C, s2idle, T2 Touch ID.

Not Apple Silicon. Not 13" T2 (`16,2`). Not T1. Official [mac-support](https://omarchy.org/manual/mac-support/) still says full-disk wipe and omits this model.

You need a **wired USB keyboard** on the Mac (Recovery, LUKS, Limine **e**/F10, black panel) and **two USB sticks**: installer ≥8 GB (the ISO **erases** it) and a private stick (keybags + this toolbox — never gist, never the installer).

---

## Easy path

One command on **macOS**, then two on **Linux**. The commands **check** what Apple and the machine expose, print a pass/fail line, and **ask a yes on each remaining gate** (default is **no**). `--yes` skips those waits, **not** the machine checks.

Do these **before** the first command (the script cannot set them):

1. Backup this Mac (Time Machine or a clone).
2. Recovery (**Command-R**) → Startup Security Utility → **No Security** and **Allow booting from external or removable media**.
3. Enroll Touch ID. Note `id -u` (often **501**).
4. Plug **two USB sticks** and the **wired keyboard** into the Mac. Lid **open**, Mac **plugged in**.

### 1. macOS — one command

```bash
git clone https://github.com/jean-humann/omarchi-dbi-mac-16-1.git
cd omarchi-dbi-mac-16-1
./bin/mbp16-1 macos
```

`macos` **stops** if the model is not `MacBookPro16,1`, if Secure Boot is still Full/Medium, if external boot is disallowed, if fewer than two USB disks are plugged, or if no Touch ID prints are enrolled. It **asks you to type y** for backup, keyboard + lid, Recovery (only if it could not read both T2 knobs), Touch ID (only if `bioutil` did not report prints), and continuing on battery. Then it maps disks, shrinks APFS if needed, writes keybags **and this toolbox** onto KEYBAGS, downloads pinned 4.0.3, and `dd`s the installer (you type that disk id again before erase).

Shut down **~30 s**. Power on, hold **Option**, pick **orange EFI Boot**. Installer disk = **Free space** (keep macOS). Not entire disk. Not Apple’s ~300 MB EFI.

### 2. Linux — two commands

Keep KEYBAGS plugged.

```bash
cd /run/media/$USER/KEYBAGS/omarchi-dbi-mac-16-1
chmod +x bin/mbp16-1
./bin/mbp16-1 setup
# reboot unplugged onto linux-t2-mbp161 (do not suspend on stock linux-t2)
./bin/mbp16-1 apply touchid
```

`setup` checks DMI, AMD DPM / amdgpu blacklist, and AC; then asks a yes for USB keyboard, no-suspend until `linux-t2-mbp161`, and not using Omarchy Hybrid GPU / Fingerprint. It also asks keyboard layout and USB-C once. `apply touchid` **refuses** until that kernel is running with DPM **low** and T2 NCM is present; then it asks that KEYBAGS with *this* Mac’s export is plugged.

If the **lid is black**: USB keyboard, Limine **e**, `module_blacklist=amdgpu`, **F10**, login, `setup`, reboot **without** that token, `setup` again.

Do **not** publish keybags, catacomb archives, `T2_TOUCHID_HOST`, serials, or unredacted `t2-touchid-doctor` output.

Later, after `omarchy update` (recovery `linux-t2` may move): `mbp16-1-limine-quiet`, then `mbp16-1 update kernel` if daily is behind.

---

## Detailed guide

Same install, unpacked. Use these sections and **subcommands** (`macos shrink`, `macos flash`, `apply gpu`, `doctor`) when you need one piece or a rerun. Skip this if the easy path is enough.

**Daily kernel:** `linux-t2-mbp161` (Watanare `linux-t2` + yuters `e77b03f` `0001`–`0005`). Identity is **pkgbase**, not a version string — it will move when you rebase.  
**Recovery:** stock `linux-t2`. Do not suspend on stock.

| | Typical on this model |
| --- | --- |
| iGPU | Intel UHD 630 at `00:02.0` — lid + compositor |
| dGPU | AMD 5500M `1002:7340` at `03:00.0` — USB-C DisplayPort |
| Wi-Fi | BCM4364 `14e4:4464` (`brcmfmac`) |
| Touch Bar | USB `05ac:8302`, **configuration 1** |
| Keyboard in this recipe | Apple ISO **French** — skip keyboard files if yours is not that board |
| Lid | Intel **Apple Color LCD**. Connector name **flips** |
| External in this recipe | LG HDR 4K on AMD, 3840×2160@60, scale 1.5, **above** the lid |

USB-C DP is **wired to AMD**. Intel cannot light a USB-C monitor. Measure PCI and connector **names on your machine**. Pin Hyprland outputs by **description**, never `eDP-*` / `DP-*`.

1. [Confirm the Mac](#1-confirm-the-mac)
2. [Phase A — macOS](#2-phase-a--macos-before-the-installer)
3. [Phase B — installer](#3-phase-b--write-the-stick-and-install)
4. [Phase C — first Linux](#4-phase-c--first-linux-panel-usb-c-dpm-typing)
5. [Phase D — sleep kernel](#5-phase-d--s2idle-wi-fi-fans-sleep-kernel)
6. [Phase E — Touch ID](#6-phase-e--touch-id)
7. [Order of operations](#7-order-of-operations)
8. [If Linux is wiped](#8-if-linux-is-wiped-later)
9. [Files](#9-files-this-setup-uses)
10. [Leave out](#10-leave-out)
11. [Sources](#11-sources)

---

## 1. Confirm the Mac

On **this** 16,1, in macOS:

```bash
sysctl -n hw.model
# must print: MacBookPro16,1
```

| ID | Machine |
| --- | --- |
| **16,1 / A2141** | This recipe |
| 16,2 | 13" 2020 T2, no dGPU |
| 16,4 | 16" 2020 + 5600M |
| 13,x / 14,x | T1 — T1Bridge only |

**Do not** use Asahi, `omarchy-mac-setup`, or Try Omarchy (Apple Silicon). **Do not** install T1Bridge. Official [mac-support](https://omarchy.org/manual/mac-support/) still says full-disk wipe and omits A2141. Omarchy 4 **Free space** is the dual-boot path ([#7666](https://github.com/omacom/omarchy/discussions/7666) on 16,2).

Randy ([novuon/mbp2019-omarchy](https://github.com/novuon/mbp2019-omarchy)) is GPU + DPM `low` + Touch Bar. Sleep here is yuters **`e77b03f`**, not Randy 06, not yuters `main`. Touch ID is [jean-humann `mbp161-mixed-envelope`](https://github.com/jean-humann/t2-touchid-linux/tree/mbp161-mixed-envelope).

---

## 2. Phase A — macOS, before the installer

The [Easy path](#easy-path) already runs **`mbp16-1 macos`**. This section is the same work unpacked, plus **subcommands** when you need one piece.

Human first: **A1 backup**, **A2 Recovery**, **A3 enroll Touch ID**. Then plug the sticks (**A0**). `macos` checks A2/A3/USB and asks a yes on each remaining gate before **A4–A5**. Do not follow A0→A5 as a time order.

```bash
./bin/mbp16-1 macos
```

Maps **internal APFS** and **two USB whole disks** first (not a keyboard, not `disk0` — TTY, seconds), then **shrink** (if the hole is short) → **export** keybags **and this toolbox** onto the **private** stick → download pinned Omarchy **4.0.3** → `dd` the **installer**. Those long jobs stay **serial** on the internal SSD (shrink relocates the volume that holds `/Users` and the ISO cache). `--yes` skips confirm waits, not the T2/USB/Touch ID checks, and still needs `--container diskNsM --installer diskN --private diskM`. Type each identifier to confirm. `--iso PATH` skips the download. `--dry-run` prints actions.

Subcommands (one piece):

```bash
./bin/mbp16-1 macos --installer disk2 --private disk3
./bin/mbp16-1 macos sticks          # list only
./bin/mbp16-1 macos shrink          # map + limits; add --keep 360g to apply
./bin/mbp16-1 macos export          # keybags + toolbox onto --private
./bin/mbp16-1 macos flash           # ISO + dd installer (needs --installer and --private)
./bin/mbp16-1 macos guide           # human checklist
```

### A0. Two USB sticks

Need **two USB disks**, not a keyboard. A wired USB keyboard is a third device and does **not** count.

| Stick | Role |
| --- | --- |
| **Installer** (`--installer`) | **≥8 GB.** Omarchy ISO (~6.3 GB) is `dd`’d here. **Erases all data** on that stick (every partition, every file). Orange EFI afterward. |
| **Private** (`--private`) | ExFAT `KEYBAGS`: `t2-touchid-export/` (keybags + catacomb), `omarchi-dbi-mac-16-1/` (this toolbox), `START-HERE.txt`. Never gist the tars. Never the installer disk. **Not** wiped by the ISO flash. |

`macos` refuses the same disk for both roles, refuses internal/non-USB, refuses an installer smaller than the ISO, and will not write tars or the toolbox onto the installer volume. You must confirm the installer identifier. If the private stick has no filesystem, it asks to erase **that disk only** as ExFAT `KEYBAGS`.

### A1. Backup

Time Machine or a clone of **this** Mac. FileVault may stay on.

### A2. Recovery: allow Linux

**Set** in Recovery only. Booted macOS cannot change T2 policy, and Recovery is another OS — reboot would kill the script. `mbp16-1 macos` and `doctor` **check** the knobs before shrink when Apple exposes them (`mdmclient QuerySecurityInfo` for both; `nvram …:AppleSecureBootPolicy` for Secure Boot: `%00` No Security, `%01` Medium, `%02` Full). They **stop** if Secure Boot is still Full/Medium or external boot is disallowed. If External Boot is unread, they still ask you to confirm Startup Security Utility.

You need **both** options (they are independent): **No Security** (Intel secure-boot evaluation) and **Allow booting from external or removable media** (USB Option-boot).

1. Shut down. Power on, hold **Command-R** (local recoveryOS on the internal SSD — not a USB installer, not Internet Recovery).
2. Utilities → **Startup Security Utility** → authenticate (Secure Enclave–backed admin).
3. **No Security**. **Allow booting from external or removable media**.
4. Restart into macOS, then run `macos`.

Without this, Option-boot will not show the orange EFI stick.

### A3. Enroll Touch ID

Human only (finger on the sensor). `macos` cannot enroll prints. System Settings → Touch ID. Note `id -u` (often **501**). `macos` reads `bioutil -c` when it can and **stops** if it sees zero prints; if unread, it asks you to confirm. Do not delete prints later unless you re-export keybags.

### A4. Shrink APFS — unallocated space

**Do not** create a Linux partition in Disk Utility. The installer wants a **hole on the partition map**.

Included in `mbp16-1 macos` **after** the TTY maps, **before** export/ISO: it **maps** the internal APFS physical store (usually `disk0s2` on this model — never a USB stick, never whole `disk0`), reads `resizeContainer limits`, and shrinks if the hole is short. Do not download the ISO or walk keybags while that relocate is running.

| | |
| --- | --- |
| Floor | **32 GB** unallocated (`--free` cannot go below this) |
| Request | **80 GB** (`--free 80g`, override e.g. `--free 120g`) |
| Or set the new APFS size | `--keep 360g` (must still leave ≥32 GB free) |
| Map | `--container disk0s2` (required with `--yes`) |

Standalone: `mbp16-1 macos shrink` (map + limits) or `mbp16-1 macos shrink --keep 360g`.

**Time:** `limits` is seconds. The shrink relocates live APFS. Typical on this 16,1 SSD: **20–40 minutes** for ~80 GB. Allow **1–2 hours** if the disk is full or local Time Machine snapshots exist. Progress often sits still, then finishes.

Keep the Mac **plugged in**, lid **open**. Do **not** sleep, close the lid, or force-shutdown.

By hand:

```bash
diskutil list internal physical
diskutil apfs resizeContainer disk0s2 limits
sudo diskutil apfs resizeContainer disk0s2 360g
diskutil list disk0    # free space AFTER the APFS container, not a new volume
```

If `limits` cannot shrink enough, delete local Time Machine snapshots and retry.

### A5. Export keybags + catacomb + toolbox (private USB)

Included in `mbp16-1 macos` (onto `--private`, **after** shrink, **before** the ISO download). Standalone: `mbp16-1 macos export` or `macos export --private diskN`. Do this while still in macOS, Data mounted. After dual-boot, Data may be unmounted — then:

```bash
diskutil list
diskutil mount disk0s3   # confirm on *your* map
```

```bash
./bin/mbp16-1 macos export
```

| Step | What | Time |
| --- | --- | --- |
| Clone (first run) | t2-touchid-linux into `~/.cache/mbp16-1` | usually **under a minute** |
| Keybags | `sudo find` for `*.kb`, then a small tar | typically **2–10 min**, little output |
| Catacomb | tar of `/Library/Catacomb` with **`--no-reboot`** | typically **1–3 min** |
| Toolbox | shareable pack onto `--private` as `omarchi-dbi-mac-16-1/` | seconds |

Without `--private`, `macos export` writes the tars to `~/Desktop/t2-touchid-export` and **does not** copy the toolbox.

Administrator password required. The upstream catacomb helper’s default **freezes `biometrickitd` and reboots now** — the toolbox does **not**. `mbp16-1 macos` writes both archives **and** the shareable toolbox onto the **private** stick after shrink and **before** it downloads or flashes the ISO. Confirm Touch ID still works before you **shut down ~30 s** (after flash if you are still inside `macos`). Do **not** shut down between export and flash.

---

## 3. Phase B — write the stick and install

### B0. Write Omarchy 4 to USB

`mbp16-1 macos` already downloaded pinned **4.0.3** (`SHA256 03d60bc74306dca51f96e1a84b690871d8d606826b260edd0208962da8507d14`) from `https://iso.omarchy.org/omarchy-4.0.3.iso` and flashed the **installer** disk. Re-flash only:

```bash
./bin/mbp16-1 macos flash --installer diskN --private diskM
```

`--private` is required so it cannot `dd` the keybag stick. Identify disks with `macos sticks` first.

By hand (do not overwrite the private stick or the Mac’s SSD):

```bash
# Linux (sdX = the installer stick, not a partition, not the private keybag disk)
lsblk -d -o NAME,TRAN,SIZE,MODEL,RM
sudo dd if=omarchy.iso of=/dev/sdX bs=4M status=progress conv=fsync oflag=direct

# macOS (N = the installer disk number; use rdisk for speed)
diskutil unmountDisk /dev/diskN
sudo dd if=omarchy.iso of=/dev/rdiskN bs=4m
```

Plug the stick **and** a **USB keyboard** into the **16,1** (keyboard on the Mac, not only a dock).

**Do not** choose entire disk (destroys macOS / SEP recovery). **Do not** reuse Apple’s ~300 MB EFI as `/boot`.

### B1. Boot

Shut down. Power on, hold **Option (⌥)**. Pick **orange EFI Boot**. If nothing orange: A2 was skipped, or wrong ISO.

Installer UI is typically **10–20 minutes** after you confirm the disk.

### B2. Installer choices

| Prompt | Choice |
| --- | --- |
| Disk | **Free space**. Not APFS. Not entire disk |
| LUKS | Default on is fine |
| Bootloader | New **2 GiB `OMARCHY_EFI`** |
| User | Remember Linux password; Touch ID sudo later also needs the **macOS** password |

The installer pulls `linux-t2`, T2 audio, Broadcom firmware, `t2fanrd`, in-tree Touch Bar. It does **not** configure hybrid gmux. That is Phase C.

### B3. If macOS still always wins

Limine lives on **`OMARCHY_EFI`**, not Apple’s ESP. From Linux, once you can boot it:

```bash
findmnt /boot
ls -l /boot/EFI/*/BOOTX64.EFI
sudo mkdir -p /boot/EFI/BOOT
# copy THIS volume’s Limine EFI into the removable-media path (adjust source if ls showed another dir)
sudo cp /boot/EFI/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
```

Hold **Control** while selecting that volume in the Option picker to set it as default. Option-boot macOS when you need SEP recovery.

---

## 4. Phase C — first Linux (panel, USB-C, DPM, typing)

Firmware muxes the panel to AMD. First graphical boot can be **black**. Intel lid + AMD loaded, DPM **`low`**. Finish this **before** any suspend and **before** Touch ID.

The [Easy path](#easy-path) already runs **`mbp16-1 setup`**. Individual `apply …` commands below are if you need one piece.

```bash
cd /run/media/$USER/KEYBAGS/omarchi-dbi-mac-16-1
chmod +x bin/mbp16-1
./bin/mbp16-1 setup
# one piece:
./bin/mbp16-1 apply gpu
./bin/mbp16-1 apply display
./bin/mbp16-1 apply desktop
./bin/mbp16-1 doctor
```

**Do not** run Trigger → Hybrid GPU / `supergfxctl` (ASUS mux). **Do not** put PCI `by-path` in `AQ_DRM_DEVICES` (Aquamarine splits on `:`). **Do not** disable `eDP-1`/`eDP-2` by name. **Do not** write DPM `auto`.

### C0. If the panel is black

USB keyboard, Limine **e**, add a space:

```text
module_blacklist=amdgpu
```

**F10**. Log in. Temporary. After C2, reboot **without** it so AMD is present for DPM (C5).

### C1. Confirm PCI (do not copy card numbers from blogs)

```bash
cat /sys/class/dmi/id/product_name
# MacBookPro16,1

lspci -nn -s 00:02.0
# Intel UHD 630

lspci -nn -s 03:00.0
# AMD Navi 14. Randy’s installer expects 0x7340 (5500M).
# A 5300M is a different ID — skip the DPM installer if it is not 7340.
```

Do not assume `/dev/dri/card1` is Intel. Card numbers move.

### C2. apply gpu — Intel through gmux + Aqua

```bash
./bin/mbp16-1 apply gpu
```

Writes gmux `force_igd`, DRM aliases, backlight udev, Aqua list, hides Hybrid GPU. Ends with **mkinitcpio + limine-update (1–3 min)**. Prefer `modprobe.d`, not cmdline-only `force_igd`.

By hand (same files):

```bash
echo 'options apple_gmux force_igd=1' | sudo tee /etc/modprobe.d/apple-gmux.conf

sudo tee /etc/udev/rules.d/70-intel-igpu.rules <<'EOF'
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:00:02.0", SYMLINK+="dri/intel-igpu"
EOF

sudo tee /etc/udev/rules.d/71-amd-dgpu.rules <<'EOF'
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:03:00.0", SYMLINK+="dri/amd-dgpu"
EOF

sudo tee /etc/udev/rules.d/90-omarchy-gmux-backlight.rules <<'EOF'
SUBSYSTEM=="backlight", KERNEL=="gmux_backlight", TAG+="uaccess"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=drm

mkdir -p ~/.config/uwsm
printf '%s\n' 'export AQ_DRM_DEVICES=/dev/dri/intel-igpu:/dev/dri/amd-dgpu' > ~/.config/uwsm/env-hyprland

sudo mkinitcpio -P    # 1–3 min
sudo limine-update
```

Names must be **colon-free**. A PCI `by-path` never opens AMD.

Hide Hybrid GPU (`~/.config/omarchy/extensions/omarchy-menu.jsonc`):

```jsonc
"trigger.hardware.hybrid-gpu": {
  "when": "false",
  "description": "Hidden on this T2 16,1. Do not run omarchy toggle hybrid gpu."
}
```

Brightness keys write **`gmux_backlight`**, not `appletb_backlight`. No ALS daemon (IIO `als` exists, unused). Idle DPMS and Hyprland `cm_auto_hdr=1` can look like auto-brightness. Omarchy idle is stock (screensaver 150 s, lock 300 s). Night light: Super+Ctrl+N.

### C3. Reboot without the amdgpu blacklist

Unplugged. Kernel should log `apple_gmux: Switching to IGD`.

```bash
ls -l /dev/dri/intel-igpu /dev/dri/amd-dgpu
readlink -f /dev/dri/intel-igpu
# must be PCI 0000:00:02.0

echo "$AQ_DRM_DEVICES"
# /dev/dri/intel-igpu:/dev/dri/amd-dgpu

hyprctl monitors all
./bin/mbp16-1 doctor
```

Leave **amdgpu loaded**. Connector **name flips**: lid-only start → Intel often `eDP-2`; cable-in start → Intel often `eDP-1`. Never disable by name.

The GPU list must be set **before** Hyprland starts (`udevadm trigger` on a running Intel-only session is not enough).

### C4. apply display — USB-C plug timing and layout

```bash
./bin/mbp16-1 apply display
# lid-only:  --external no
# known panel: --external-desc 'LG Electronics LG HDR 4K'
```

It asks whether you use USB-C. **No** writes lid-only (Color LCD + phantom eDP helper). **Yes** pins that monitor by `hyprctl` description (LG HDR 4K gets 3840×2160@60 / scale 1.5 / above the lid). Never copies a panel you do not have.

**Do not** start Hyprland with AMD in Aqua **and** the cable already in (black lid, `amdgpu` `err 28`).

1. **Unplug** the USB-C monitor.
2. Log in. Lid = Intel **Apple Color LCD**. Both DRM cards must already be open.
3. Plug a **left** Thunderbolt 3 port.
4. Disable only the phantom eDP (**empty description**). Never **Apple Color LCD**.

Daily: unplug before logout/reboot; plug after the lid is up.

Edit `desc:` / `position` if your panel is not this LG. Catch-all `auto` puts the next head to the **right**.

```lua
-- ~/.config/hypr/monitors.lua
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = "auto"
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

hl.monitor({
  output = "desc:Apple Computer Inc Color LCD",
  mode = "3072x1920@60",
  position = "0x0",
  scale = 2,
})

hl.monitor({
  output = "desc:LG Electronics LG HDR 4K",
  mode = "3840x2160@60",
  position = "auto-center-up",
  scale = 1.5,
})
```

Hardware cursors on the 5500M are a black square — prepend into `looknfeel.lua` (do not replace the whole Omarchy file):

```lua
hl.config({
  cursor = { no_hardware_cursors = true },
})
```

```lua
-- append to ~/.config/hypr/autostart.lua
o.launch_on_start(os.getenv("HOME") .. "/.local/bin/mbp16-1-hypr-outputs --watch")
```

Toolbox `apply display` copies [`files/home/.local/bin/mbp16-1-hypr-outputs`](files/home/.local/bin/mbp16-1-hypr-outputs) (needs `jq` + `socat`; `mbp16-1 deps` installs both). By hand, copy that same file to `~/.local/bin/`.

Intel-primary idle is ~**4 W** on the 5500M with a display attached; firmware AMD-as-panel is ~14–18 W.

### C5. apply power — DPM low + mbp16-1-powerd

**After** Intel owns the panel and AMD is probed (C3). **Do not** run this with `amdgpu` still blacklisted.

```bash
./bin/mbp16-1 apply power
```

Randy’s oneshot checks DMI + `7340` at `03:00.0`, writes **`low`**, never **`auto`**. On this topology `auto` has hung the SMU. First `cargo build --release` for powerd: **1–3 min**. Super is the only power UI. **Do not** install TLP / auto-cpufreq / watt.

If `03:00.0` is **not** `7340`, do not run Randy’s installer. You may write `low` by hand if the sysfs node exists — still never `auto`.

By hand (DPM only):

```bash
git clone https://github.com/novuon/mbp2019-omarchy
cd mbp2019-omarchy
sudo scripts/install-02-amd-power-management

cat /sys/bus/pci/devices/0000:03:00.0/power_dpm_force_performance_level
# low
```

Do not bounce `low`/`high` from `gpu_busy_percent`. Do not install `mbp161-amdgpu-dpm-governor` unless work runs **on** the 5500M (`DRI_PRIME=1`).

```bash
omarchy-powerprofiles-set ac balanced
```

| Super | Idle desk | Many busy cores | Skin hard stop |
| --- | --- | --- | --- |
| power-saver | 22 W, `power` | 32 W, `balance_power` | 40 °C |
| **balanced** (AC here) | **40 W**, `balance_power` | 58 W, `balance_performance` | 43 °C |
| performance | 45 W, `balance_performance` | 80 W, `performance` | 43 °C |

Never writes DPM, `no_turbo`, fans, `brcmfmac`, `t2bce`. Status: `cat /run/mbp16-1-powerd/status`. Stop restores firmware PL1 **100 W**.

### C6. apply input — keyboard, trackpad, SDDM

```bash
./bin/mbp16-1 apply input
# skip the question:
./bin/mbp16-1 apply input --layout skip      # not Mac AZERTY
./bin/mbp16-1 apply input --layout fr-mac    # Apple ISO French
```

The command asks. **No** keeps trackpad + DWT + software-cursor greeter and leaves your layout alone. **Yes** writes `fr(mac)` + `hid_apple iso_layout=1`. `apply sleep` then omits `hid_apple.iso_layout=1` from the cmdline if you skipped.

Omarchy writes PC `fr`. `hid_apple iso_layout=-1` swaps `<>` and `@#` on ISO.

`~/.config/hypr/input.lua`:

```lua
hl.config({
  input = {
    kb_layout = "fr",
    kb_variant = "mac",
    kb_options = "compose:caps,shift:both_capslock_cancel",
    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,
    sensitivity = 0.25,
    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },
})

hl.device({
  name = "apple-inc.-apple-internal-keyboard-/-trackpad-1",
  natural_scroll = true,
  scroll_factor = 0.4,
  sensitivity = 0.25,
})
```

Do **not** set `scroll_factor` negative.

`/etc/vconsole.conf`: `KEYMAP=mac-fr`, `XKBLAYOUT=fr`, `XKBVARIANT=mac`.

```text
# /etc/modprobe.d/hid_apple.conf
options hid_apple iso_layout=1 fnmode=2
```

Also last on the Limine cmdline in D1: `hid_apple.iso_layout=1`. Stop fcitx5 before rewriting `~/.config/fcitx5/profile` (`keyboard-fr-mac`).

DWT: the pad is USB `05ac:0340` on `t2bce_vhci` and is tagged external unless:

```
# /etc/udev/hwdb.d/71-mbp16-1-touchpad.hwdb
touchpad:usb:v05acp0340:*
 ID_INPUT_TOUCHPAD_INTEGRATION=internal
```

```
# /etc/libinput/local-overrides.quirks
[Apple T2 Internal Keyboard]
MatchName=Apple Inc. Apple Internal Keyboard / Trackpad
MatchUdevType=keyboard
MatchBus=usb
MatchVendor=0x05AC
MatchProduct=0x0340
AttrKeyboardIntegration=internal
```

```bash
sudo systemd-hwdb update
sudo udevadm trigger --subsystem-match=input
```

Then **log out** (`hyprctl reload` is not enough).

SDDM is a second Hyprland as user `sddm`. **Do not** edit `/usr/share/sddm/hyprland.lua`. Use `/etc/sddm/hyprland-mbp16-1.lua` (`fr(mac)` + software cursor) and `/etc/sddm.conf.d/20-mbp16-1-greeter.conf` (in [`files/etc/sddm/`](files/etc/sddm/)).

### C7. Touch Bar — stay on USB config 1

**Do not** switch to `tiny-dfr` / USB config 2 until the rest of the desktop is boring.

```bash
lsusb | grep 8302
# 05ac:8302
```

Optional still-config-1 media-strip: [Randy 09](https://github.com/novuon/mbp2019-omarchy/blob/main/docs/fixes/09-touch-bar.md).

---

## 5. Phase D — s2idle, Wi-Fi, fans, sleep kernel

The [Easy path](#easy-path) `setup` already writes D1–D3 and runs `apply kernel --build`. Use the `apply sleep` / `apply kernel` **subcommands** below for a rerun.

Stock Omarchy 4 wants `deep`. This 16,1 wants **s2idle**. Stock `linux-t2` **cannot** resume the 5500M SMU while `amdgpu` is bound (**SMU `-62`**). Sleep is a **second** kernel beside stock.

**Do not** replace `linux-t2`. **Do not** run yuters `install.sh` or current **`main`**. **Do not** leave `mem_sleep_default=deep`. **Do not** `rmmod brcmfmac` (BCM4377 hack). **Do not** unload `t2bce` / `t2_sep_transport`. After SMU `-62`, **do not suspend again**.

If you already ran `setup` or `apply desktop`, D1–D3 files are in place. Still **do not suspend**. Jump to [D4](#d4-apply-kernel---build) only if the sleep kernel was skipped.

### D1. apply sleep — cmdline, lid, systemd (do not suspend)

```bash
./bin/mbp16-1 apply sleep
```

Writes Limine drop-ins, logind lid (`HandleLidSwitch=suspend` undocked), systemd `MemorySleepMode=s2idle`, `usbcore autosuspend=-1`, and **`mbp16-1-lock-rearm.service`** (`sleep.target` ExecStop: `try-restart fprintd`, not the T2 transport). Then **mkinitcpio + limine-update (1–3 min)**, then `mbp16-1-limine-quiet` (`timeout: 1`, `quiet: yes`). Re-run that helper after **`omarchy update`** or `omarchy refresh limine` (both rewrite `/boot/limine.conf`). Do not use `timeout: 0`.

**Do not suspend and do not close the lid** until `linux-t2-mbp161` is running. After D1, a lid close is a real suspend; stock `linux-t2` can SMU **`-62`**.

Limine drop-ins: **`/etc/limine-entry-tool.d/`**, **`+=` only**. A `KERNEL_CMDLINE[default]=` in `/etc/default/limine` **wipes** drop-ins. Later drop-ins **prepend**; name s2idle `00-` so it stays **last**.

```bash
# /etc/limine-entry-tool.d/t2-mac.conf  — no deep
KERNEL_CMDLINE[default]+=" intel_iommu=on iommu=pt pm_async=off"

# /etc/limine-entry-tool.d/00-mbp16-1-sleep.conf  — apply sleep generates this.
# Omit hid_apple.iso_layout=1 if you skipped Apple ISO French.
KERNEL_CMDLINE[default]+=" mem_sleep_default=s2idle pcie_ports=compat hid_apple.iso_layout=1"

# /etc/modprobe.d/omarchy-usb-autosuspend.conf
options usbcore autosuspend=-1
```

```ini
# /etc/systemd/logind.conf.d/30-mbp16-1-lid.conf
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=ignore
```

```ini
# /etc/systemd/sleep.conf.d/90-mbp16-1-s2idle.conf
[Sleep]
MemorySleepMode=s2idle
```

Undocked → s2idle (once on `linux-t2-mbp161`). Docked → clamshell. Letters **do not** wake. Wake = **power / Touch ID key** (ACPI) or RTC. Keep `brcmfmac` bound.

```bash
sudo limine-update
cat /sys/power/mem_sleep
# [s2idle] deep     ← s2idle selected
```

`apply sleep` skips Limine `BOOT_ORDER` until `linux-t2-mbp161` is installed; `apply kernel --build` writes it.

### D2. apply wifi

BCM4364: keep **`brcmfmac` bound**. **Do not** install `broadcom-wl`. T2 NCM (Touch ID) is `cdc_ncm` on `05ac:8233`.

```bash
./bin/mbp16-1 apply wifi
```

```text
# /etc/modprobe.d/brcmfmac.conf
options brcmfmac feature_disable=0x82000
```

### D3. apply fans

`t2fanrd` Fan1 **and** Fan2, Intel package. Loud 30–60 s at boot until userspace. **Linear 40–85 °C** (not Omarchy stock 55–75). Do not exponential. Do not “fix” with DPM `auto` / `no_turbo` / unloading `t2bce`. Hunt: raise `low_temp` toward 46 then 48; never shrink `high_temp` to 75.

```bash
./bin/mbp16-1 apply fans
```

```ini
# /etc/t2fand.conf
[Fan1]
low_temp=40
high_temp=85
speed_curve=linear
always_full_speed=false

[Fan2]
low_temp=40
high_temp=85
speed_curve=linear
always_full_speed=false
```

```bash
sudo systemctl restart t2fanrd.service
```

You can run this as soon as the first Linux boot is usable if the fans are screaming.

### D4. apply kernel --build

First `makepkg` on this 8-core 16,1: typically **45–90 minutes**. Plugged in. Do not suspend mid-build.

| Piece | Source |
| --- | --- |
| Base | Watanare [linux-t2-arch](https://github.com/NoaHimesaka1873/linux-t2-arch) — whatever stock `linux-t2` is on the box after you rebase |
| t2linux | `T2_PATCH_HASH` from that linux-t2-arch revision |
| Intel-primary | yuters **`e77b03f` `0001`–`0005`** after t2linux |
| This kernel only | `CONFIG_RUST` **off**, `pkgbase=linux-t2-mbp161`, does **not** `provides=(linux)` |

This pack **vendors** one linux-t2-arch snapshot for the first install (`apply kernel --build`). That snapshot may be older than the recovery `linux-t2` already on the box — expected. After the first boot onto mbp161, `doctor` Kernel notes behind → `update kernel`. Do not pin the running `uname -r` string in scripts — it changes on every rebase (`…-Watanare-T2-<pkgrel>-t2-mbp161`).

| Patch | Role |
| --- | --- |
| `0001` | mux panel to Intel before DRM binds |
| `0002` | skip amdgpu fbdev when panel is on iGPU |
| `0003` | skip detect/HPD/EDID on ghost eDP |
| `0004` | leave AMD `7340` + HDMI audio untouched across s2idle (else SMU `-62`) |
| `0005` | Titan Ridge Type3. Go2Sx `-110` expected |

```bash
./bin/mbp16-1 apply kernel --build
# packaging only: ./bin/mbp16-1 apply kernel
# hand: cd ~/src/linux-t2-mbp161 && makepkg -si && sudo limine-update && mbp16-1-limine-quiet
```

`--build` also writes `/etc/limine-entry-tool.d/zz-mbp16-1-boot-order.conf`, runs `limine-update` (1–3 min), then `mbp16-1-limine-quiet` (`timeout: 1`, `quiet: yes` — `limine-update` would otherwise restore the menu):

```bash
BOOT_ORDER="linux-t2-mbp161, linux-t2, *fallback, Snapshots"
```

Do **not** run [yuters `install.sh`](https://github.com/yuters/mbp161-hybrid-graphics) (PCI `by-path` Aqua). Do not use current **`main`** (Falcon / panel-on-AMD / DPM `auto`).

### D4b. After `omarchy update` (stock linux-t2 moves)

These are **two different commands**. `omarchy update` is the distro. `mbp16-1 update kernel` is the daily sleep kernel. One does not do the other.

Do **not** run raw `pacman -Syu` — Omarchy’s hook blocks it. The bar refresh icon only watches the `omarchy` package; pending `linux-t2` still needs `omarchy update`.

```bash
omarchy update                  # or: omarchy update -y
mbp16-1-limine-quiet            # pkexec; limine-update rewrites /boot/limine.conf
./bin/mbp16-1 doctor
```

That upgrades **recovery** `linux-t2` (and headers, plus whatever else pacman has). Daily `linux-t2-mbp161` stays on the tree you last built. Drop-ins (`t2-mac.conf`, s2idle, `BOOT_ORDER`) stay; `/boot/limine.conf` `timeout`/`quiet` do **not** — that is the manual step. Do not suspend on the new stock kernel. Do not reboot onto it as daily.

Then, if doctor Kernel notes behind:

```bash
./bin/mbp16-1 update kernel --check
./bin/mbp16-1 update kernel       # fetch linux-t2-arch, keep yuters 0001–0005, makepkg
```

`--force` rebuilds even if versions already match. `update kernel` copies `pkgver` / `pkgrel` / `T2_PATCH_HASH` / kernel checksums / `config.x86_64` from linux-t2-arch. It keeps `pkgbase=linux-t2-mbp161`, yuters patches, `CONFIG_RUST` off, and does **not** `provides=(linux)`.

If a yuters patch **rejects** on the new t2linux base, stop. Those five patches need a refresh. Do **not** switch to yuters `main`.

### D5. Reboot onto linux-t2-mbp161 and prove s2idle

Reboot **unplugged**. Daily default is `linux-t2-mbp161`. Pick stock `linux-t2` only for recovery.

```bash
uname -r
# ends with -t2-mbp161  (the prefix is the linux-t2 version you built)

cat /sys/power/mem_sleep
# [s2idle] deep

./bin/mbp16-1 doctor
```

Never from a script. After SMU `-62` in `dmesg` / journal: **stop**. Unplugging the monitor does **not** fix stock. A second suspend after `-62` can hang with no resume log (hard reset).

1. Two clean **lid-only** `systemctl suspend` cycles (or undocked lid-close).
2. Then one with USB-C attached. Attached-display 0005: [yuters#1](https://github.com/yuters/mbp161-hybrid-graphics/issues/1). Fallback `mbp161_tb_type3=0 mbp161_tb_bypass=1` was **not** needed on the 5500M + this LG.

Letters do not wake. Wake = **power / Touch ID key** (ACPI, not Linux biometrics) or RTC.

---

## 6. Phase E — Touch ID

The [Easy path](#easy-path) second Linux command is **`mbp16-1 apply touchid`**. It **refuses** until `linux-t2-mbp161` is running, DPM is **low**, and T2 NCM is present, then asks that KEYBAGS from **this** Mac is plugged.

Start only when: Intel panel, phantom eDP disabled by empty description, DPM **`low`**, s2idle works on **`linux-t2-mbp161`**, `cdc_ncm` exists, keybags from **this** Mac (private USB).

**Do not** run Omarchy Setup → Fingerprint. **Do not** unload `t2_sep_transport` or start a second transport this boot.

```bash
ip -br link    # T2 cdc_ncm, not wlan
./bin/mbp16-1 apply touchid
```

Clone is usually **under a minute**. `install.sh` is **a few minutes** (packages, units, `/etc/t2-touchid.conf`). If it exits asking you to edit that file (NCM iface, **BridgeOS** link-local peer, macOS uid, special bag), edit it and rerun `apply touchid`. Leave s2idle. PAM: [`docs/PAM_AUTH.md`](https://github.com/jean-humann/t2-touchid-linux/blob/mbp161-mixed-envelope/docs/PAM_AUTH.md).

16,1 envelope: length **100**, header `0x50`, version **1**. Digest **`v1-skip-cal`**. First mute often `-110` (no 30 s shutdown after macOS Touch ID). **One transport start per boot.**

By hand if not using the toolbox:

```bash
git clone -b mbp161-mixed-envelope https://github.com/jean-humann/t2-touchid-linux.git
cd t2-touchid-linux
sudo ./install.sh
```

First bring-up — disable autostart for one controlled start:

```bash
sudo systemctl disable fprintd.service t2-sep-transport.service \
  t2-keybag-load.service t2-credential-unlock.service \
  t2-biometric-ready.service
```

```bash
sudo t2-touchid-provision-catacomb /private/path/t2-touchid-catacomb.tar.gz
sudo tools/check-t2-linux-readiness.sh   # RESULT: READY
sudo systemctl start t2-sep-transport.service
ls -l /dev/t2-aks
```

| Error | Meaning | What to do |
| --- | --- | --- |
| **`-110`** (~12 s) | Mute | **Stop.** Do not unload. macOS → confirm Touch ID → shut down ~30 s → Linux; `/dev/t2-aks` absent before another start |
| **`-71`** | Envelope mix | Fork accepts 16,1 (v2-sized header, v1 version) |
| **`-74`** | Hash miss | Probe `v1-skip-cal`, then `v1-body` / `v1-zero-cal`. If all fail, stop |

```bash
sudo systemctl start t2-keybag-load.service
sudo t2-keybag-unlock
sudo systemctl start fprintd.service
fprintd-verify -f any "$USER"
```

Use **`-f any`**. Keep a **root shell** on another TTY:

```bash
sudo tools/install-pam.sh
omarchy restart shell
pkexec bash -c 'id -u'
pkexec bash -c 'id -u'   # second still fingerprint
```

| Action | Lid open | Lid closed |
| --- | --- | --- |
| `sudo` | fingerprint, then password | password only |
| `pkexec` | fingerprint, then password | password only |
| Super+Ctrl+L lock | fingerprint | still fingerprint |

A second **sudo** / **pkexec** while another is already on the sensor waits (up to 32 s) instead of falling through to password. Start the second command after the first has claimed (about a second), not in the same instant. The lock screen does not cause that wait. Do not overlap a finger press with a password.

After **lid-close s2idle**, user.slice was frozen so fingerprint PAM / fprintd VerifyFinger can be stuck while the lock still looks secure. Omarchy’s `lock lock` IPC is a no-op when already locked, so it cannot reset PAM. `mbp16-1-lock-rearm.service` runs on `sleep.target` stop (after thaw, not from a frozen `system-sleep` hook): `systemctl try-restart fprintd` (not the T2 transport) so lock PAM errors and retries, then warms `fprintd-list`. First finger press after wake is ACPI only if you used the Touch ID key to wake — open the lid, wait for the fingerprint square, then place the finger. Do not unload transport.

---

## 7. Order of operations

The [Easy path](#easy-path) is the order (`macos` → Option-boot **Free space** → `setup` → reboot `linux-t2-mbp161` → `apply touchid`). This list is the same sequence with phase letters for the sections above.

1. Confirm `MacBookPro16,1` (`macos` / `setup` refuse otherwise).
2. **A** Backup; Recovery No Security + external media (**set** in Recovery; `macos` checks and asks if unread); enroll Touch ID; `macos`.
3. **B** Option → orange EFI → **Free space**.
4. **Linux:** `mbp16-1 setup` from KEYBAGS (if the lid is black: Limine blacklist once, setup, reboot without it, setup again).
5. Reboot unplugged onto **`linux-t2-mbp161`**. Two lid-only + one attached s2idle. Not on stock.
6. **E** `apply touchid` (refuses until daily kernel / DPM low / NCM), then catacomb from `t2-touchid-export/`. Not Omarchy Fingerprint.

`setup` is gpu → display → input → fans → wifi → power → sleep, then `apply kernel --build`, unless this boot still has `module_blacklist=amdgpu` (GPU files only, then reboot). `doctor` and the `apply …` pieces are for checks and reruns.

---

## 8. If Linux is wiped later

macOS remains SEP recovery. Reinstalling Omarchy means re-exporting keybags if `/var/lib/t2-touchid` is gone. A macOS reinstall can change fingerprints; export again. Re-apply Phase C onward (Randy / Hyprland / kernel files are not in the Omarchy ISO).

---

## 9. Files this setup uses

| File | Role |
| --- | --- |
| `/etc/modprobe.d/apple-gmux.conf` | `force_igd=1` |
| `/etc/modprobe.d/hid_apple.conf` | `iso_layout=1 fnmode=2` |
| `/etc/modprobe.d/brcmfmac.conf` | WPA workaround |
| `/etc/modprobe.d/omarchy-usb-autosuspend.conf` | `autosuspend=-1` |
| `/etc/udev/rules.d/70-intel-igpu.rules` | `/dev/dri/intel-igpu` |
| `/etc/udev/rules.d/71-amd-dgpu.rules` | `/dev/dri/amd-dgpu` |
| `/etc/udev/rules.d/90-omarchy-gmux-backlight.rules` | lid brightness |
| `~/.config/uwsm/env-hyprland` | Aqua Intel then AMD |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | hide Hybrid GPU |
| `~/.config/hypr/monitors.lua` | lid / external by `desc:` (generated) |
| `~/.config/hypr/looknfeel.lua` | software cursors (prepend) |
| `~/.config/hypr/autostart.lua` | `hypr-outputs --watch` (append) |
| `~/.config/hypr/input.lua` | `fr(mac)`, sensitivity 0.25 |
| `~/.config/hypr/input-trackpad.lua` | trackpad-only prepend (`--layout skip`) |
| `~/.config/fcitx5/profile` | `keyboard-fr-mac` (French only) |
| `~/.local/bin/mbp16-1-hypr-outputs` | disable empty-description eDP (`jq` + `socat`) |
| `~/.local/bin/mbp16-1-lock-rearm` | after s2idle, warm `fprintd-list` as the session user |
| `/usr/lib/mbp16-1/lock-rearm` | `try-restart fprintd` then that helper (not T2 transport) |
| `/etc/systemd/system/mbp16-1-lock-rearm.service` | `sleep.target` ExecStop — after thaw, not a frozen `system-sleep` hook |
| `~/.local/bin/mbp16-1-limine-quiet` | Limine `timeout: 1`, `quiet: yes` |
| `/etc/vconsole.conf` | `KEYMAP=mac-fr` (French only) |
| `/etc/t2fand.conf` | linear 40–85 |
| `/etc/mbp16-1-powerd.conf` | Super envelopes |
| `/etc/systemd/system/mbp16-1-powerd.service` | occupancy + skin RAPL/EPP |
| `/etc/limine-entry-tool.d/t2-mac.conf` | IOMMU, **no** `deep` |
| `/etc/limine-entry-tool.d/00-mbp16-1-sleep.conf` | `s2idle` last (**generated** by `apply sleep`, not copied from `files/`) |
| `/etc/limine-entry-tool.d/zz-mbp16-1-boot-order.conf` | mbp161 first (after kernel package exists) |
| `/etc/systemd/logind.conf.d/30-mbp16-1-lid.conf` | undocked suspend / docked ignore |
| `/etc/systemd/sleep.conf.d/90-mbp16-1-s2idle.conf` | `MemorySleepMode=s2idle` |
| `mbp2019-amdgpu-power-prep.service` | DPM `low` |
| `/etc/sddm/hyprland-mbp16-1.lua` | greeter layout + cursor (French) |
| `/etc/sddm.conf.d/20-mbp16-1-greeter.conf` | points SDDM at that Lua |
| `/etc/sddm/hyprland-mbp16-1-nolayout.lua` | greeter cursor only (`--layout skip`) |
| `/etc/sddm.conf.d/20-mbp16-1-greeter-nolayout.conf` | points SDDM at that Lua |
| `/etc/udev/hwdb.d/71-mbp16-1-touchpad.hwdb` | DWT internal |
| `/etc/libinput/local-overrides.quirks` | T2 keyboard internal |
| `/etc/pam.d/sudo`, `polkit-1`, lock stacks | Touch ID |

---

## 10. Leave out

Optional extras, not this recipe. Dangerous substitutes are called out in the phase where they would appear.

| Thing | Why |
| --- | --- |
| Extra USB-C heads / Studio Display | Different DP/DSC; do not copy DPM `high`/`auto` |
| `mbp161-amdgpu-dpm-governor` | Only if work runs on the 5500M |
| Titan Ridge `mbp161_tb_bypass=1` | Not needed when 0005 + display is clean |
| Linux ALS / clight / wluma | Unused on purpose |
| Changing idle 150/300 s | Stock Omarchy |
| `hid_appletb_kbd` | Optional config-1 media-strip |

---

## 11. Sources

| | |
| --- | --- |
| Dual-boot | Omarchy 4 Free space; [mac-support](https://omarchy.org/manual/mac-support/) (stale wipe); [#7666](https://github.com/omacom/omarchy/discussions/7666) |
| Randy | [novuon/mbp2019-omarchy](https://github.com/novuon/mbp2019-omarchy) 01 / 02 / 09. 03–08 stubs |
| t2linux | [hybrid-graphics](https://wiki.t2linux.org/guides/hybrid-graphics/), [postinstall](https://wiki.t2linux.org/guides/postinstall/), [Wi-Fi](https://wiki.t2linux.org/guides/wifi-bluetooth/) |
| USB-C same model | [Dan Wahlin](https://blog.codewithdan.com/how-i-cut-gpu-power-from-18-w-to-4-w-on-an-omarchy-macbook-pro-with-github-copilot-cli/) |
| Lid names | [sk3pper](https://sk3pper.github.io/posts/workstation-setup/lid-close-freeze-on-t2-mbp19/); [omarchy#7855](https://github.com/omacom/omarchy/discussions/7855) |
| Sleep kernel | [yuters `e77b03f`](https://github.com/yuters/mbp161-hybrid-graphics/blob/e77b03fe0902216a7544208f2988b4cd391423a1/kernel/README.md). Not [`main`](https://github.com/yuters/mbp161-hybrid-graphics). [yuters#1](https://github.com/yuters/mbp161-hybrid-graphics/issues/1) |
| Touch ID | [jean-humann `mbp161-mixed-envelope`](https://github.com/jean-humann/t2-touchid-linux/tree/mbp161-mixed-envelope); [`docs/PAM_AUTH.md`](https://github.com/jean-humann/t2-touchid-linux/blob/mbp161-mixed-envelope/docs/PAM_AUTH.md) |

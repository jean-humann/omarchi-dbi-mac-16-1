# macOS (on the 16,1)

**Easy path** (one command): see the parent [README Easy path](../README.md#easy-path).
`./bin/mbp16-1 macos` checks model, T2 policy, USB disks, AC, and Touch ID
enrollments; asks a **yes** on each remaining gate; then shrink → export → ISO → flash.

Recovery **set** and Touch ID **enroll** stay human. `macos` cannot change T2 policy
from a booted session. It **stops** if Secure Boot is still Full/Medium, external
boot is disallowed, fewer than two USB disks are plugged, or `bioutil` sees zero
prints.

This page is the **subcommands** and the human checklist.

The exporter reuses
[t2-touchid-linux](https://github.com/jean-humann/t2-touchid-linux) `tools/macos`.
`macos`, `macos guide`, `macos flash`, `help`, `doctor`, and `apply` print a compact
square Omarchy mark ([`icon.txt`](icon.txt)) on the left and three lines on the
right: **Omarchy dual-boot installer**, MacBookPro16,1 · keep macOS, ISO version.
The mark is Omarchy’s official
[`icon.png`](https://github.com/basecamp/omarchy/blob/master/icon.png) (thin
black strokes on green), thresholded at native size, dilated, then Braille.

1. Backup this Mac (`macos` asks you to confirm).
2. Recovery (Command-R, internal recoveryOS) → Startup Security Utility → **No Security** and **Allow booting from external or removable media**. `macos` cannot set this; it checks before shrink.
3. Enroll Touch ID. Note `id -u`. `macos` stops if it sees zero prints.
4. If Data is unmounted after dual-boot: `diskutil mount disk0s3` (confirm on *your* map).
5. Plug **two USB sticks** (not the keyboard): an **8 GB or larger** installer (will be **fully erased**), and a private stick for keybags **and this toolbox**. Mac **plugged in**, lid **open**. Then:

```bash
./bin/mbp16-1 macos
# one piece:
./bin/mbp16-1 macos sticks
./bin/mbp16-1 macos shrink          # map + limits; --keep 360g to apply
./bin/mbp16-1 macos export --private diskM
./bin/mbp16-1 macos flash --installer diskN --private diskM
./bin/mbp16-1 macos --container disk0s2 --free 80g --installer diskN --private diskM
```

That one-shot **maps** internal APFS (never a USB stick) and both USB roles, **shrinks**
if free space is below 80 GB (will not go below the 32 GB floor or macOS recommended
minimum), **exports** keybags **and the shareable toolbox** onto the private stick, **downloads** the ISO (~6.3 GB,
SHA-256 `03d60bc74306dca51f96e1a84b690871d8d606826b260edd0208962da8507d14`), then **`dd`s** the ISO onto the installer. That flash **erases all
data** on the installer stick. `--yes` needs `--container`, `--installer`, and
`--private`. It skips confirm waits, not the machine checks.

`--private` is never flashed. Keybags are never written onto the installer volume.
The toolbox lands in `omarchi-dbi-mac-16-1/` next to `t2-touchid-export/`. Never gist those tars. Do **not** create a Linux partition in the APFS hole.

6. After `macos` finishes: confirm Touch ID, shut down ~30 s, then Option-boot the orange EFI stick. Installer disk = **Free space**. First Linux command: `mbp16-1 setup` from KEYBAGS (`START-HERE.txt`).

Prose: [install guide](../README.md) — Easy path first, then Detailed guide §2–§3.

# apply phases. Sourced from bin/mbp16-1.

reload_udev() {
  run as_root udevadm control --reload-rules
  run as_root udevadm trigger --subsystem-match=drm || true
  run as_root udevadm trigger --subsystem-match=input || true
}

rebuild_boot() {
  expect "Rebuild initramfs + Limine UKIs" \
    "mkinitcpio -P then limine-update, then mbp16-1-limine-quiet (timeout: 1, quiet: yes)." \
    "Typically 1–3 minutes per installed kernel (stock linux-t2, plus linux-t2-mbp161 if present)." \
    "Little output at times — wait it out. Do not rewrite /etc/default/limine with KERNEL_CMDLINE[default]= ."
  if command -v mkinitcpio >/dev/null 2>&1; then
    run as_root mkinitcpio -P
  fi
  if command -v limine-update >/dev/null 2>&1; then
    run as_root limine-update
  fi
  kernel_limine_quiet
}

# Omarchy 4.5 drops t2bce_vhci from every boot image (omacom/omarchy#17755),
# so the built-in keyboard is dead at the LUKS prompt. The drop-in sorts after
# zz-omarchy-kernel-modules.conf and adds it back as optional. Callers rebuild.
install_luks_keyboard() {
  install_root_file "$FILES/etc/mkinitcpio.conf.d/zzz-mbp16-1-t2bce.conf" \
    /etc/mkinitcpio.conf.d/zzz-mbp16-1-t2bce.conf
}

apply_luks() {
  require_16_1
  is_linux || die "apply luks is Linux-only"
  ensure_core
  expect "LUKS keyboard (t2bce_vhci in the boot image)" \
    "Adds t2bce_vhci? after Omarchy's zz-omarchy-kernel-modules.conf (omacom/omarchy#17755)." \
    "Ends with mkinitcpio + limine-update (1–3 min). Keep the USB keyboard for the next unlock." \
    "Do not edit zz-omarchy-kernel-modules.conf by hand; this drop-in wins without touching it."
  install_luks_keyboard
  rebuild_boot
  if ((APPLY_BUNDLE == 0)); then
    confirm_ready "Next boot" \
      "Type the LUKS passphrase on the built-in keyboard once to confirm." \
      "Then: mbp16-1 doctor   (Kernel → LUKS keyboard reads each boot image)"
  fi
}

# Titan Ridge xHCI (8086:15ec) stays in D0: in D3hot it never signals PME on a
# USB-C plug. ~0.34 W idle (klizas). Re-run add so this boot picks it up.
install_titan_ridge_awake() {
  install_root_file "$FILES/etc/udev/rules.d/72-mbp16-1-titan-ridge.rules" \
    /etc/udev/rules.d/72-mbp16-1-titan-ridge.rules
  run as_root udevadm control --reload-rules
  run as_root udevadm trigger --action=add --subsystem-match=pci \
    --attr-match=vendor=0x8086 --attr-match=device=0x15ec || true
}

apply_gpu() {
  require_16_1
  is_linux || die "apply gpu is Linux-only"
  ensure_core
  precheck_gpu
  expect "GPU routing (Intel lid, AMD loaded)" \
    "Writes gmux force_igd, DRM aliases, backlight udev, Aqua list, hides Hybrid GPU." \
    "Also the LUKS keyboard drop-in (t2bce_vhci, omacom/omarchy#17755)." \
    "Ends with mkinitcpio + limine-update (1–3 min)." \
    "Do not: Omarchy Hybrid GPU / supergfxctl, PCI by-path in AQ_DRM_DEVICES, DPM auto."
  install_root_file "$FILES/etc/modprobe.d/apple-gmux.conf" /etc/modprobe.d/apple-gmux.conf
  install_root_file "$FILES/etc/udev/rules.d/70-intel-igpu.rules" /etc/udev/rules.d/70-intel-igpu.rules
  install_root_file "$FILES/etc/udev/rules.d/71-amd-dgpu.rules" /etc/udev/rules.d/71-amd-dgpu.rules
  install_root_file "$FILES/etc/udev/rules.d/90-omarchy-gmux-backlight.rules" /etc/udev/rules.d/90-omarchy-gmux-backlight.rules
  install_user_file "$FILES/home/.config/uwsm/env-hyprland" "$HOME/.config/uwsm/env-hyprland"
  install_luks_keyboard
  hide_hybrid_gpu
  reload_udev
  rebuild_boot
  if ((APPLY_BUNDLE == 0)); then
    confirm_ready "Next boot" \
      "Unplug USB-C if it is connected." \
      "Reboot WITHOUT module_blacklist=amdgpu (Limine e, delete that token if you added it)." \
      "Then: mbp16-1 apply display   and   mbp16-1 apply power"
  fi
}

# Omarchy 4.0 had one menu key (trigger.hardware.hybrid-gpu). 4.5 shows
# hybrid-gpu-on / hybrid-gpu-off whenever omarchy-hw-hybrid-gpu sees two GPUs,
# which is always true here. Hide all three; merge into an existing file.
HYBRID_GPU_MENU_KEYS=(
  trigger.hardware.hybrid-gpu
  trigger.hardware.hybrid-gpu-on
  trigger.hardware.hybrid-gpu-off
)

hybrid_gpu_hidden() {
  local dest="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc" key
  for key in "${HYBRID_GPU_MENU_KEYS[@]}"; do
    file_has "$dest" "\"${key}\"" || return 1
  done
}

hide_hybrid_gpu() {
  local dest="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
  mkdir -p "$(dirname "$dest")"
  if hybrid_gpu_hidden; then
    log "Hybrid GPU already hidden" "${HYBRID_GPU_MENU_KEYS[*]}"
    return 0
  fi
  if [[ ! -f $dest ]]; then
    install_user_file "$FILES/home/.config/omarchy/extensions/omarchy-menu.jsonc" "$dest"
    return 0
  fi
  backup_if_exists "$dest"
  if ((DRY_RUN)); then
    log "dry-run: merge hybrid-gpu hide into $dest"
    return 0
  fi
  python3 - "$dest" "${HYBRID_GPU_MENU_KEYS[@]}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
keys = sys.argv[2:]
text = path.read_text()
missing = [k for k in keys if f'"{k}"' not in text]
if not missing:
    raise SystemExit(0)
entry = (
    '  "{}": {{\n'
    '    "when": "false",\n'
    '    "description": "Hidden on this T2 16,1. Do not run omarchy toggle hybrid gpu."\n'
    '  }}'
)
block = ",\n".join(entry.format(k) for k in missing)
idx = text.rfind("}")
if idx < 0:
    path.write_text("{\n" + block + "\n}\n")
    raise SystemExit(0)
before = text[:idx].rstrip()
if not before.endswith("{") and not before.endswith(","):
    before += ","
path.write_text(before + "\n" + block + "\n" + text[idx:])
PY
  log "hid Trigger → Hybrid GPU in $dest" "${HYBRID_GPU_MENU_KEYS[*]}"
}

apply_power() {
  require_16_1
  is_linux || die "apply power is Linux-only"
  ensure_core
  ensure_rust
  local use_randy=1
  if precheck_power; then
    use_randy=1
  else
    use_randy=0
  fi
  expect "AMD DPM low + mbp16-1-powerd" \
    "Randy installer pins DPM low (never auto) on 5500M 7340. First powerd cargo build: 1–3 min." \
    "Do not install TLP / auto-cpufreq / watt. Super menu is the only power UI."
  local dpm="/sys/bus/pci/devices/${AMD_PCI}/power_dpm_force_performance_level"
  if ((use_randy)); then
    ensure_randy
    if systemctl is-enabled mbp2019-amdgpu-power-prep.service >/dev/null 2>&1 &&
      [[ -r $dpm && $(<"$dpm") == low ]]; then
      log "Randy DPM service already pinning low"
    else
      log "running Randy install-02-amd-power-management (writes low, never auto)"
      run as_root "$CACHE/mbp2019-omarchy/scripts/install-02-amd-power-management"
    fi
  elif [[ -r $dpm && $(<"$dpm") != low ]]; then
    if ask_yn "Not a 5500M 7340. Write DPM low to sysfs now? (never auto)" y; then
      printf 'low\n' | run as_root tee "$dpm" >/dev/null
      log "wrote DPM low (no Randy oneshot — this will not persist unless you add one)"
    fi
  fi
  apply_powerd
  if command -v omarchy-powerprofiles-set >/dev/null 2>&1; then
    if ((ASSUME_YES)) || ask_yn "Set AC Super profile to balanced?" y; then
      # polkit allows switch-profile only from the active desktop session, so
      # this fails over SSH. It is a preference: do not stop setup for it.
      run omarchy-powerprofiles-set ac balanced ||
        warn "AC Super profile not set" \
          "polkit refuses it outside the desktop session. Later, in a desktop terminal: omarchy-powerprofiles-set ac balanced"
    else
      log "left AC Super profile unchanged"
    fi
  fi
}

apply_powerd() {
  local crate="$ROOT/mbp16-1-powerd"
  [[ -f $crate/Cargo.toml ]] || die "missing $crate"
  ensure_rust
  expect "Compile mbp16-1-powerd" \
    "First cargo build --release: typically 1–3 minutes (longer if crates are not cached)." \
    "Never writes AMD DPM or no_turbo. Super menu stays the only power UI."
  if ((DRY_RUN)); then
    log "dry-run: cargo build --release in $crate"
    return 0
  fi
  (cd "$crate" && cargo build --release)
  run as_root install -m 0755 "$crate/target/release/mbp16-1-powerd" /usr/local/sbin/mbp16-1-powerd
  run as_root install -m 0644 "$crate/mbp16-1-powerd.conf" /etc/mbp16-1-powerd.conf
  run as_root install -m 0644 "$crate/mbp16-1-powerd.service" /etc/systemd/system/mbp16-1-powerd.service
  run as_root systemctl daemon-reload
  run as_root systemctl enable mbp16-1-powerd.service
  # restart, not enable --now: a running daemon would keep the old binary/conf.
  run as_root systemctl restart mbp16-1-powerd.service
}

apply_display() {
  require_16_1
  is_linux || die "apply display is Linux-only"
  ensure_core
  maybe_reuse_config
  resolve_external
  save_apply_config
  expect "USB-C / Hyprland outputs" \
    "Lid is always pinned as Apple Color LCD. USB-C is optional and pinned by description." \
    "Do not disable Apple Color LCD by eDP-* name. Do not start Hyprland with the cable already in."
  install_user_file "$FILES/home/.local/bin/mbp16-1-hypr-outputs" "$HOME/.local/bin/mbp16-1-hypr-outputs" 0755
  write_monitors_lua
  prepend_if_missing "$HOME/.config/hypr/looknfeel.lua" \
    "$FILES/home/.config/hypr/looknfeel-cursor.lua" \
    no_hardware_cursors
  local line
  line=$(tr -d '\n' <"$FILES/home/.config/hypr/autostart-line.lua")
  mkdir -p "$HOME/.config/hypr"
  if file_has "$HOME/.config/hypr/autostart.lua" 'mbp16-1-hypr-outputs'; then
    log "autostart already launches hypr-outputs"
  else
    backup_if_exists "$HOME/.config/hypr/autostart.lua"
    if ((DRY_RUN)); then
      log "would append hypr-outputs to autostart.lua"
    else
      printf '%s\n' "$line" >>"$HOME/.config/hypr/autostart.lua"
      log "appended hypr-outputs to autostart.lua"
    fi
  fi
  if ((APPLY_BUNDLE == 0)); then
    section "Daily"
    hint "Login unplugged; plug USB-C after the lid is up."
    hint "Never disable Apple Color LCD by eDP-* name."
    if [[ $EXTERNAL == yes ]]; then
      hint "Edit monitors.lua if desc:${EXTERNAL_DESC} is wrong."
    fi
  fi
}

apply_input() {
  require_16_1
  is_linux || die "apply input is Linux-only"
  ensure_core
  maybe_reuse_config
  resolve_layout
  save_apply_config
  expect "Keyboard, trackpad, SDDM" \
    "Trackpad + disable-while-typing on every 16,1. French ISO files only if you said yes." \
    "Then log out once — hyprctl reload is not enough for DWT."
  install_root_file "$FILES/etc/udev/hwdb.d/71-mbp16-1-touchpad.hwdb" /etc/udev/hwdb.d/71-mbp16-1-touchpad.hwdb
  install_root_file "$FILES/etc/libinput/local-overrides.quirks" /etc/libinput/local-overrides.quirks
  run as_root systemd-hwdb update
  reload_udev
  install_sddm_greeter
  if [[ $LAYOUT == skip ]]; then
    log "skipping fr(mac) keyboard files"
    prepend_if_missing "$HOME/.config/hypr/input.lua" \
      "$FILES/home/.config/hypr/input-trackpad.lua" \
      'sensitivity = 0.25'
  else
    install_root_file "$FILES/etc/modprobe.d/hid_apple.conf" /etc/modprobe.d/hid_apple.conf
    install_root_file "$FILES/etc/vconsole.conf" /etc/vconsole.conf
    install_user_file "$FILES/home/.config/hypr/input.lua" "$HOME/.config/hypr/input.lua"
    local skip_fcitx=0
    if command -v fcitx5 >/dev/null 2>&1 && pgrep -u "$USER" -x fcitx5 >/dev/null 2>&1; then
      if ask_yn "fcitx5 is running and will overwrite its profile on exit. Stop it now?" y; then
        systemctl --user stop fcitx5.service 2>/dev/null || true
      else
        skip_fcitx=1
        warn "skipping fcitx5 profile"
      fi
    fi
    if ((skip_fcitx == 0)); then
      install_user_file "$FILES/home/.config/fcitx5/profile" "$HOME/.config/fcitx5/profile"
    fi
  fi
  if ((APPLY_BUNDLE == 0)); then
    confirm_ready "Log out once" \
      "hyprctl reload is not enough for disable-while-typing and SDDM." \
      "Log out (or reboot) so the new hwdb tags apply."
  fi
}

apply_fans() {
  require_16_1
  is_linux || die "apply fans is Linux-only"
  ensure_core
  expect "Fans (t2fanrd)" \
    "Linear 40–85 °C on Fan1 and Fan2 (Intel package). Not Omarchy stock 55–75." \
    "Loud 30–60 s at boot until userspace is expected." \
    "Do not 'fix' with DPM auto, no_turbo, or unloading t2bce."
  install_root_file "$FILES/etc/t2fand.conf" /etc/t2fand.conf
  if systemctl list-unit-files t2fanrd.service >/dev/null 2>&1; then
    run as_root systemctl restart t2fanrd.service
  else
    warn "t2fanrd.service not installed (Omarchy T2 package usually provides it)"
    if ! ask_yn "Keep /etc/t2fand.conf anyway?" y; then
      log "left t2fand.conf as written; start t2fanrd later"
    fi
  fi
}

apply_wifi() {
  require_16_1
  is_linux || die "apply wifi is Linux-only"
  ensure_core
  local pci
  if command -v lspci >/dev/null 2>&1; then
    # Whole listing first. lspci -nn | grep -q dies of SIGPIPE (141) once its
    # output passes one buffer, and pipefail then hides the BCM4364.
    pci=$(lspci -nn 2>/dev/null || true)
    if [[ $pci == *'14e4:4488'* ]]; then
      die "PCI shows BCM4377 (14e4:4488)" \
        "This brcmfmac snippet is for 16,1 BCM4364 (14e4:4464). Do not copy 4377 suspend unloads here."
    fi
    if [[ $pci != *'14e4:4464'* ]]; then
      warn "did not see BCM4364 14e4:4464 on PCI" "continuing with the 16,1 brcmfmac workaround anyway"
      if ! ask_yn "Install brcmfmac feature_disable=0x82000 anyway?" n; then
        log "skipped wifi snippet"
        return 0
      fi
    fi
  fi
  expect "Wi-Fi (BCM4364 / brcmfmac)" \
    "Keep brcmfmac bound. Do not install broadcom-wl." \
    "Do not unload on suspend — that hack is for BCM4377."
  install_root_file "$FILES/etc/modprobe.d/brcmfmac.conf" /etc/modprobe.d/brcmfmac.conf
}

install_lock_rearm() {
  install_user_file "$FILES/home/.local/bin/mbp16-1-lock-rearm" "$HOME/.local/bin/mbp16-1-lock-rearm" 0755
  install_root_file "$FILES/usr/lib/mbp16-1/lock-rearm" /usr/lib/mbp16-1/lock-rearm 0755
  install_root_file "$FILES/etc/systemd/system/mbp16-1-lock-rearm.service" \
    /etc/systemd/system/mbp16-1-lock-rearm.service
  if [[ -e /usr/lib/systemd/system-sleep/mbp16-1-lock-rearm ]]; then
    run as_root rm -f /usr/lib/systemd/system-sleep/mbp16-1-lock-rearm
    log "removed system-sleep lock-rearm (runs frozen; would stall resume)"
  fi
  if ((DRY_RUN)); then
    log "dry-run: systemctl enable mbp16-1-lock-rearm.service"
    return 0
  fi
  run as_root systemctl daemon-reload
  run as_root systemctl enable mbp16-1-lock-rearm.service
}

apply_sleep() {
  require_16_1
  is_linux || die "apply sleep is Linux-only"
  ensure_core
  maybe_reuse_config
  resolve_layout
  expect "Sleep policy (s2idle)" \
    "Writes Limine drop-ins, logind lid, systemd MemorySleepMode, usbcore autosuspend=-1, lock-rearm." \
    "Keeps the Titan Ridge xHCI awake so USB-C plugs are seen (~0.34 W idle)." \
    "Quiets Limine after limine-update. Do not suspend on stock linux-t2." \
    "Do not close the lid until linux-t2-mbp161 is running — after this, lid-close is a real suspend." \
    "Do not put mem_sleep_default=deep back. After SMU -62, do not suspend again."
  install_root_file "$FILES/etc/modprobe.d/omarchy-usb-autosuspend.conf" /etc/modprobe.d/omarchy-usb-autosuspend.conf
  install_titan_ridge_awake
  install_root_file "$FILES/etc/limine-entry-tool.d/t2-mac.conf" /etc/limine-entry-tool.d/t2-mac.conf
  write_sleep_dropin
  install_root_file "$FILES/etc/systemd/logind.conf.d/30-mbp16-1-lid.conf" /etc/systemd/logind.conf.d/30-mbp16-1-lid.conf
  install_root_file "$FILES/etc/systemd/sleep.conf.d/90-mbp16-1-s2idle.conf" /etc/systemd/sleep.conf.d/90-mbp16-1-s2idle.conf
  install_lock_rearm
  if pacman -Q "$KERNEL_PKGBASE" >/dev/null 2>&1; then
    kernel_write_boot_order
  else
    warn "${KERNEL_PKGBASE} not installed yet — skip boot order. Run: mbp16-1 apply kernel --build"
  fi
  rebuild_boot
  if ((APPLY_BUNDLE == 0)); then
    confirm_ready "Do not suspend yet" \
      "Sleep files are in place, but stock linux-t2 cannot resume the 5500M (SMU -62)." \
      "Do not close the lid. Next: mbp16-1 apply kernel --build, reboot onto linux-t2-mbp161, then two lid-only s2idle."
  fi
}

apply_kernel() {
  require_16_1
  is_linux || die "apply kernel is Linux-only"
  ensure_core
  case ${1:-} in
    ""|--build) ;;
    --pkg)
      kernel_pkg_install "${2:-}"
      return
      ;;
    *) die "unknown apply kernel flag ${1}" "use --build, or --pkg [DIR] (default kernel/prebuilt)" ;;
  esac
  local dest
  dest=$(kernel_build_dest)
  expect "${KERNEL_PKGBASE} packaging" \
    "Copies PKGBUILD + ${KERNEL_PATCHES_DESC} only. Stock ${KERNEL_STOCK} stays installed." \
    "First install from the vendored tree. After ${KERNEL_STOCK} moves: mbp16-1 update kernel." \
    "Do not run yuters install.sh or current yuters main (panel on AMD, DPM auto, by-path Aqua)."
  if [[ ${1:-} == --build ]]; then
    ensure_kernel_build_tools
  fi
  if ((DRY_RUN)); then
    log "dry-run: copy $KERNEL_DIR → $dest"
    if [[ ${1:-} == --build ]]; then
      log "dry-run: makepkg -si in $dest, boot order (drop-in + /etc/default/limine), limine-update"
    else
      log "dry-run: packaging only (add --build to compile, or mbp16-1 update kernel to rebase)"
    fi
    return 0
  fi
  kernel_copy_packaging
  if [[ ${1:-} == --build ]]; then
    kernel_makepkg_install
  else
    section "Next"
    hint "mbp16-1 apply kernel --build     45–90 min, plugged in (vendored tree)"
    hint "mbp16-1 apply kernel --pkg       CI packages from kernel/prebuilt/, no compile"
    hint "mbp16-1 update kernel            rebase onto current linux-t2-arch, then makepkg"
    hint "or: cd $dest && makepkg -si && sudo limine-update && mbp16-1-limine-quiet"
    hint "after a hand build, re-run: mbp16-1 apply sleep   (boot order: drop-in + /etc/default/limine)"
  fi
}

apply_touchid() {
  require_16_1
  is_linux || die "apply touchid is Linux-only"
  ensure_touchid_build_tools
  precheck_touchid
  expect "Touch ID userspace (t2-touchid-linux)" \
    "Clones jean-humann mbp161-mixed-envelope if needed (usually under a minute)." \
    "install.sh is a few minutes: packages, units, /etc/t2-touchid.conf." \
    "Do not run Omarchy Setup → Fingerprint. Do not unload t2_sep_transport." \
    "Do not start a second transport this boot."
  require_yes "KEYBAGS is plugged with t2-touchid-export/ from THIS Mac (never gist those tars)" \
    "Export is macos on this Mac. Plug the private stick, then re-run apply touchid."
  ensure_touchid
  local tree="$CACHE/t2-touchid-linux"
  if [[ ! -f /etc/t2-touchid.conf ]]; then
    log "first install.sh copies /etc/t2-touchid.conf and exits until you set NCM + BridgeOS peer"
  fi
  run as_root "$tree/install.sh" || {
    local st=$?
    if [[ $st -eq 2 ]]; then
      section "Your move" "edit /etc/t2-touchid.conf as root, then rerun: mbp16-1 apply touchid"
      step 1 "T2_TOUCHID_INTERFACE: ip -br link" "the cdc_ncm link (MAC ac:de:48:00:11:22), not wlan"
      step 2 "T2_TOUCHID_HOST: sudo nmcli device set IF managed no; sudo ip -6 addr add fe80::aede:48ff:fe00:1122/64 dev IF" \
        "NetworkManager's DHCP on that link gives up after 45 s and drops the link-local, so unmanage it and put the EUI-64 of the generic MAC back"
      step 3 "ping -6 -c2 -I IF ff02::1%IF; ip -6 neigh show dev IF" "the fe80:: neighbour that is not your own address is BridgeOS"
      step 4 "T2_TOUCHID_MACOS_USER_ID: tar -tzf KEYBAGS/t2-touchid-export/t2-touchid-catacomb.tar.gz | grep user_" \
        "user_000001f5.cat is 0x1f5 = 501; T2_TOUCHID_SPECIAL_BAG is then -501"
      return 0
    fi
    die "t2-touchid install.sh failed ($st)"
  }
  # install.sh makes /run/t2-touchid as the parent of workers/, so it gets 0755.
  # t2-touchid-provision-catacomb refuses anything but 0700 (keybag-load sets
  # 0700 too, but later). /run is tmpfs: this lasts until the next boot.
  run as_root install -d -o root -g root -m 0700 /run/t2-touchid
  install_lock_rearm
  # Printed for the user to paste: $USER must stay literal.
  # shellcheck disable=SC2016
  local kb='/run/media/$USER/KEYBAGS/t2-touchid-export'
  section "Next (once, this boot)" \
    "Do not unload t2_sep_transport. Do not start a second transport. Keep a root shell on another TTY before PAM."
  step 1 "sudo systemctl disable fprintd.service t2-sep-transport.service t2-keybag-load.service t2-credential-unlock.service t2-biometric-ready.service" \
    "install.sh enabled them; the readiness check fails until they are disabled for manual bring-up"
  step 2 "KB=$kb; tar -xzf \$KB/t2-keybags.tar.gz -O state/path-map.txt | grep Library/Keychains/" \
    "pick the candidate-NNNN that maps to ~/Library/Keychains/<UUID>/user.kb"
  step 3 "tar -xzf \$KB/t2-keybags.tar.gz -O state/candidate-NNNN | sudo sh -c 'umask 077; cat >/var/lib/t2-touchid/user.kb'" \
    "the readiness check wants it 600 root:root. Never gist it."
  step 4 "sudo install -m 0600 \$KB/t2-touchid-catacomb.tar.gz /root/ && sudo t2-touchid-provision-catacomb /root/t2-touchid-catacomb.tar.gz" \
    "it refuses an archive that is not 0600, and every file on the stick is world-readable. Then: sudo rm /root/t2-touchid-catacomb.tar.gz"
  step 5 "sudo systemctl start t2-biometric-port-refresh.service" \
    "once: brings up the BridgeOS link and caches the BiometricKit port. Do not repeat it."
  step 6 "sudo $tree/tools/check-t2-linux-readiness.sh" "want RESULT: READY"
  step 7 "sudo systemctl start t2-sep-transport.service" "one start; never unload. Stop on -110. Then step 6 again: want RESULT: INITIALIZED"
  step 8 "sudo systemctl start t2-keybag-load.service && sudo t2-keybag-unlock && sudo systemctl start fprintd.service" \
    "t2-keybag-unlock asks for the macOS login password"
  step 9 "fprintd-verify -f any \"\$USER\"" \
    "from a desktop terminal: over SSH the claim fails with 'caller process identity unavailable' (no active local session)"
  step 10 "sudo systemctl enable t2-sep-transport.service t2-keybag-load.service t2-credential-unlock.service t2-biometric-ready.service fprintd.service" \
    "back to the state install.sh set, so the next boot brings Touch ID up by itself"
  step 11 "sudo $tree/tools/install-pam.sh && omarchy restart shell" "then pkexec bash -c 'id -u' twice: fingerprint both times"
  hint "After each boot, the first sudo asks the Linux password, then the macOS one, to unlock the keybags."
  hint "Operator guide: $tree/docs/PAM_AUTH.md"
  if ! ask_yn "I will follow that sequence and will not unload t2_sep_transport." y; then
    die "stopped" "When you are ready: start at step 1 above. Do not skip the gate."
  fi
}

apply_desktop() {
  APPLY_BUNDLE=1
  require_16_1
  is_linux || die "apply desktop is Linux-only"
  ensure_core
  ensure_rust
  expect "apply desktop" \
    "Asks keyboard + USB-C, then writes GPU, display, input, fans, wifi, power, and sleep files." \
    "Randy DPM installer + first powerd cargo build: a few minutes." \
    "Ends with mkinitcpio + limine-update (1–3 min). Does not compile linux-t2-mbp161." \
    "Do not: DPM auto, Hybrid GPU / supergfxctl, yuters install.sh, Omarchy Fingerprint."
  situate_desktop
  apply_gpu
  apply_display
  apply_input
  apply_fans
  apply_wifi
  apply_power
  apply_sleep
  section "Done"
  hint "Desktop files written (gpu, display, input, fans, wifi, power, sleep)."
  hint "Keyboard: ${LAYOUT}    USB-C: ${EXTERNAL}${EXTERNAL_DESC:+  ($EXTERNAL_DESC)}"
  if ((APPLY_SETUP)); then
    return 0
  fi
  confirm_ready "Reboot unplugged" \
    "No module_blacklist=amdgpu on the next boot." \
    "Log in with USB-C unplugged; plug after the lid is up." \
    "Still needed: mbp16-1 apply kernel --pkg (CI packages) or --build (45–90 min), then Touch ID." \
    "Do not suspend until linux-t2-mbp161 is running."
}

mbp16_1_setup() {
  APPLY_SETUP=1
  require_16_1
  is_linux || die "setup is Linux-only" "On macOS: mbp16-1 macos"
  expect "setup" \
    "Installs missing runtimes, then the 16,1 desktop files. Installs ${KERNEL_PKGBASE} if missing: CI packages from kernel/prebuilt/ when they match kernel/prebuilt.sha256, else makepkg." \
    "Asks keyboard + USB-C once. Do not suspend. Do not close the lid until that kernel is running." \
    "If this boot used module_blacklist=amdgpu, this run only writes GPU files — reboot without that token, then setup again."
  section "Checks" "Machine facts first. --yes does not skip these."
  ok "model" "$(product_name)"
  if amdgpu_blacklisted; then
    info "amdgpu" "blacklisted this boot — this run writes GPU files only, then reboot without that token"
  elif [[ -z $(dpm_level) ]]; then
    info "AMD DPM" "unbound — GPU files first"
  else
    ok "AMD DPM" "$(dpm_level)"
  fi
  if ac_is_online; then
    ok "power" "AC"
  else
    info "power" "battery — the sleep-kernel build wants AC"
  fi
  section "Confirm each" "Default is no. Type y only if that line is true."
  require_yes "A wired USB keyboard is plugged into the Mac" \
    "Need it if the lid is black, and for LUKS / Limine. Plug it into the Mac, not only a dock."
  require_yes "I will not suspend or close the lid until linux-t2-mbp161 is running" \
    "Stock linux-t2 suspend poisons the 5500M SMU. Finish setup and reboot onto linux-t2-mbp161 first."
  require_yes "I will not run Omarchy Hybrid GPU or Setup → Fingerprint" \
    "Those paths are wrong on this T2 16,1. Use this toolbox only."
  ensure_core
  ensure_rust

  if amdgpu_blacklisted || [[ -z $(dpm_level) ]]; then
    apply_gpu
    section "Next"
    hint "Reboot WITHOUT module_blacklist=amdgpu (Limine e, delete that token if you added it)."
    hint "Unplug USB-C. Log in, lid up, then: mbp16-1 setup"
    confirm_ready "Reboot without the amdgpu blacklist" \
      "AMD must bind before DPM and the rest of setup."
    return 0
  fi

  apply_desktop

  if pacman -Q "$KERNEL_PKGBASE" >/dev/null 2>&1; then
    section "Next"
    if kernel_is_daily; then
      hint "Already on ${KERNEL_PKGBASE}. Next: mbp16-1 apply touchid"
    else
      hint "Package installed, this boot is still $(kernel_running_pkgbase)."
      hint "Reboot unplugged onto ${KERNEL_PKGBASE}, then: mbp16-1 apply touchid"
      confirm_ready "Reboot onto ${KERNEL_PKGBASE}" \
        "Do not suspend on stock ${KERNEL_STOCK}."
    fi
    return 0
  fi

  local prebuilt=$KERNEL_DIR/prebuilt
  if kernel_prebuilt_verify "$prebuilt" --quiet; then
    apply_kernel --pkg "$prebuilt"
  else
    if compgen -G "$prebuilt/*.pkg.tar.zst" >/dev/null; then
      # Show why the CI packages are refused, then offer the compile.
      kernel_prebuilt_verify "$prebuilt" || true
      ask_yn "Compile ${KERNEL_PKGBASE} instead (45–90 min)" y ||
        die "stopped before the kernel" "fix kernel/prebuilt/ (README D4, Prebuilt packages), then: mbp16-1 apply kernel --pkg"
    fi
    apply_kernel --build
  fi
  section "Next"
  hint "After that reboot: mbp16-1 apply touchid"
}

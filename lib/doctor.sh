# doctor / status. Sourced from bin/mbp16-1.
# Compact: one pass line per group. Detail + Next only when something is wrong.

_doc_fail() {
  fail "$1" "$2"
  [[ -n ${3:-} ]] && ui_next "$3"
  rc=1
}

_doc_aqua() {
  local aqua=${AQ_DRM_DEVICES:-} envf
  envf="${XDG_CONFIG_HOME:-$HOME/.config}/uwsm/env-hyprland"
  if [[ -z $aqua && -f $envf ]]; then
    aqua=$(sed -n 's/^export AQ_DRM_DEVICES=//p' "$envf" | tail -n 1)
  fi
  printf '%s\n' "$aqua"
}

_doc_fr_mac_files() {
  local hypr="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/input.lua"
  file_has "$hypr" 'kb_variant = "mac"' && return 0
  grep -q 'iso_layout=1' /etc/modprobe.d/hid_apple.conf 2>/dev/null && return 0
  grep -q '^KEYMAP=mac-fr' /etc/vconsole.conf 2>/dev/null && return 0
  return 1
}

mbp16_1_doctor() {
  local model rc=0 rec=0
  ui_reset_counts
  model=$(product_name)
  ui_meta "${model}  ·  $(kernel_running_pkgbase)"

  if [[ $model != "$EXPECTED_MODEL" ]]; then
    section "Machine" "This toolbox is for the 16-inch 2019 Intel Mac (A2141)."
    _doc_fail "DMI is ${model}" "want ${EXPECTED_MODEL}  (--i-know if PCI matches)"
  fi

  if is_darwin; then
    section "Startup Security" "T2 policy. macos cannot set this — Recovery only."
    rec=0
    _macos_t2_boot_policy_state || rec=$?
    case $rec in
      0) ok "No Security  ·  external media allowed" ;;
      1)
        _doc_fail "Secure Boot=${MACOS_T2_SECURE}, external=${MACOS_T2_EXTERNAL}" \
          "want off + allowed. Command-R → Startup Security Utility" \
          "Command-R → Startup Security Utility"
        ;;
      *)
        info "could not read both knobs" \
          "Secure Boot=${MACOS_T2_SECURE}  external=${MACOS_T2_EXTERNAL}. Open Startup Security Utility if Option-boot shows no orange EFI."
        ;;
    esac
    section "Next" "Before writing Omarchy. Wired USB keyboard on the Mac."
    step 1 "Recovery (Command-R) → Startup Security Utility" "No Security + allow external media if the check above is red or unread"
    step 2 "Enroll Touch ID, note id -u"
    step 3 "Plug two USB sticks" "installer ≥8 GB (fully erased) vs private keybags + toolbox — not the keyboard"
    step 4 "mbp16-1 macos" "map APFS + USB (TTY), then shrink → export (keybags + toolbox) → ISO → flash"
    step 5 "Shut down ~30 s, Option-boot orange EFI" "installer disk = Free space (keep macOS)"
    ui_summary
    return "$rc"
  fi

  is_linux || die "doctor runs on Linux or macOS only"
  deps_report || rc=1

  local intel amd dpm aqua mem cmdline no_turbo iso
  intel=$(read_sys "/sys/bus/pci/devices/${INTEL_PCI}/vendor")
  amd=$(read_sys "/sys/bus/pci/devices/${AMD_PCI}/device")
  dpm=$(read_sys "/sys/bus/pci/devices/${AMD_PCI}/power_dpm_force_performance_level")
  mem=$(read_sys /sys/power/mem_sleep)
  cmdline=$(tr -d '\n' </proc/cmdline 2>/dev/null || true)
  aqua=$(_doc_aqua)

  # ── Graphics: hardware, then compositor routing
  section "Graphics" "Intel lid. AMD USB-C only. Never DPM auto."
  subsection "Hardware:"
  if [[ $intel == 0x8086 && $amd == "$AMD_DEVICE" && $dpm == low ]]; then
    ok "Intel lid  ·  AMD 5500M  ·  DPM low"
  else
    if [[ $intel == 0x8086 ]]; then
      ok "Intel lid at ${INTEL_PCI}"
    else
      _doc_fail "Intel missing at ${INTEL_PCI}" "mbp16-1 apply gpu" "mbp16-1 apply gpu"
    fi
    if [[ $amd == "$AMD_DEVICE" ]]; then
      ok "AMD 5500M at ${AMD_PCI}"
    elif [[ -n $amd ]]; then
      info "AMD at ${AMD_PCI} is ${amd}" "Randy installer wants ${AMD_DEVICE}; still pin DPM low"
    else
      _doc_fail "AMD missing at ${AMD_PCI}" "reboot without module_blacklist=amdgpu" "mbp16-1 apply gpu"
    fi
    if [[ $dpm == low ]]; then
      ok "DPM low"
    elif [[ $dpm == auto ]]; then
      _doc_fail "DPM is auto" "mbp16-1 apply power" "mbp16-1 apply power"
    elif [[ -n $dpm ]]; then
      _doc_fail "DPM is ${dpm} (want low)" "mbp16-1 apply power" "mbp16-1 apply power"
    else
      _doc_fail "DPM sysfs missing" "reboot without module_blacklist=amdgpu" "mbp16-1 apply gpu"
    fi
  fi

  subsection "Routing:"
  local gmux=0 drm=0 aqua_ok=0 hybrid=0
  grep -q 'force_igd=1' /etc/modprobe.d/apple-gmux.conf 2>/dev/null && gmux=1
  [[ -e /dev/dri/intel-igpu && -e /dev/dri/amd-dgpu ]] && drm=1
  [[ $aqua == /dev/dri/intel-igpu:/dev/dri/amd-dgpu ]] && aqua_ok=1
  file_has "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc" 'trigger.hardware.hybrid-gpu' && hybrid=1
  if ((gmux && drm && aqua_ok && hybrid)); then
    ok "gmux IGD  ·  intel-igpu:amd-dgpu  ·  Aqua Intel then AMD  ·  Hybrid GPU hidden"
  else
    ((gmux)) && ok "gmux force_igd=1" || _doc_fail "gmux force_igd=1 missing" "mbp16-1 setup" "mbp16-1 setup"
    ((drm)) && ok "DRM intel-igpu + amd-dgpu" || _doc_fail "DRM aliases missing" "mbp16-1 setup" "mbp16-1 setup"
    ((aqua_ok)) && ok "Aqua Intel then AMD" || \
      _doc_fail "Aqua is ${aqua:-unset}" "mbp16-1 setup" "mbp16-1 setup"
    ((hybrid)) && ok "Hybrid GPU hidden" || \
      _doc_fail "Hybrid GPU still visible" "mbp16-1 setup" "mbp16-1 setup"
  fi

  # ── Display: lid pin, phantom eDP, cursors
  section "Display" "Pin by description, never eDP-*."
  local helper=0 watch=0 cursors=0 lid=0
  [[ -x $HOME/.local/bin/mbp16-1-hypr-outputs ]] && helper=1
  file_has "$HOME/.config/hypr/autostart.lua" 'mbp16-1-hypr-outputs' && watch=1
  file_has "$HOME/.config/hypr/looknfeel.lua" 'no_hardware_cursors' && cursors=1
  file_has "$HOME/.config/hypr/monitors.lua" 'desc:Apple Computer Inc Color LCD' && lid=1
  if ((helper && watch && cursors && lid)); then
    ok "Color LCD pin  ·  phantom eDP helper  ·  software cursors"
  else
    ((lid)) && ok "Color LCD pin" || \
      _doc_fail "Lid not pinned by Color LCD" "mbp16-1 setup" "mbp16-1 setup"
    ((helper && watch)) && ok "phantom eDP helper" || \
      _doc_fail "phantom eDP helper missing" "mbp16-1 setup" "mbp16-1 setup"
    ((cursors)) && ok "software cursors" || \
      _doc_fail "software cursors missing" "mbp16-1 setup" "mbp16-1 setup"
  fi

  section "Kernel" "Daily ${KERNEL_PKGBASE}. Recovery ${KERNEL_STOCK} — do not suspend on it."
  kernel_report_versions || rc=1

  # ── Sleep: live state, then files
  section "Sleep" "s2idle only. After SMU -62, do not suspend again."
  subsection "This boot:"
  local mem_ok=0 cmd_ok=0
  [[ $mem == *'[s2idle]'* ]] && mem_ok=1
  if [[ $cmdline == *mem_sleep_default=deep* ]]; then
    _doc_fail "cmdline still has mem_sleep_default=deep" "mbp16-1 apply sleep" "mbp16-1 apply sleep"
  elif [[ $cmdline == *mem_sleep_default=s2idle* ]]; then
    cmd_ok=1
  else
    _doc_fail "cmdline missing mem_sleep_default=s2idle" "mbp16-1 apply sleep" "mbp16-1 apply sleep"
  fi
  if ((mem_ok && cmd_ok)); then
    ok "s2idle"
  else
    ((mem_ok)) || _doc_fail "mem_sleep is not s2idle" "${mem:-missing}  ·  mbp16-1 apply sleep" "mbp16-1 apply sleep"
  fi

  subsection "Files:"
  local t2mac=0 dropin=0 sd_sleep=0 lidpol=0 usb=0
  if [[ -f /etc/limine-entry-tool.d/t2-mac.conf ]] &&
    ! grep -E '^[^#]*mem_sleep_default=deep' /etc/limine-entry-tool.d/t2-mac.conf >/dev/null; then
    t2mac=1
  fi
  grep -q 'mem_sleep_default=s2idle' /etc/limine-entry-tool.d/00-mbp16-1-sleep.conf 2>/dev/null && dropin=1
  grep -q 'MemorySleepMode=s2idle' /etc/systemd/sleep.conf.d/*.conf 2>/dev/null && sd_sleep=1
  if grep -q 'HandleLidSwitch=suspend' /etc/systemd/logind.conf.d/30-mbp16-1-lid.conf 2>/dev/null &&
    grep -q 'HandleLidSwitchDocked=ignore' /etc/systemd/logind.conf.d/30-mbp16-1-lid.conf 2>/dev/null; then
    lidpol=1
  fi
  grep -Rsq 'autosuspend=-1' /etc/modprobe.d/*.conf 2>/dev/null && usb=1
  if ((t2mac && dropin && sd_sleep && lidpol && usb)); then
    ok "lid undocked suspend / docked ignore  ·  USB stay bound"
  else
    ((t2mac)) || {
      if [[ ! -f /etc/limine-entry-tool.d/t2-mac.conf ]]; then
        _doc_fail "t2-mac.conf missing" "mbp16-1 setup" "mbp16-1 setup"
      else
        _doc_fail "t2-mac.conf still has deep" "mbp16-1 apply sleep" "mbp16-1 apply sleep"
      fi
    }
    ((dropin)) || _doc_fail "sleep drop-in missing s2idle" "mbp16-1 setup" "mbp16-1 setup"
    ((sd_sleep)) || _doc_fail "systemd sleep is not s2idle" "mbp16-1 setup" "mbp16-1 setup"
    ((lidpol)) || _doc_fail "lid policy missing" "mbp16-1 setup" "mbp16-1 setup"
    ((usb)) || _doc_fail "usbcore autosuspend=-1 missing" "mbp16-1 setup" "mbp16-1 setup"
  fi
  if [[ -r /boot/limine.conf ]]; then
    if grep -q '^timeout: 1' /boot/limine.conf && grep -q '^quiet: yes' /boot/limine.conf; then
      : # quiet is fine; do not spend a row
    else
      info "Limine menu not quieted" "mbp16-1-limine-quiet  (after omarchy refresh limine)"
    fi
  fi

  section "Network" "BCM4364 / brcmfmac. Not broadcom-wl."
  if module_loaded brcmfmac && grep -q 'feature_disable=0x82000' /etc/modprobe.d/brcmfmac.conf 2>/dev/null; then
    ok "brcmfmac  ·  WPA workaround"
  else
    module_loaded brcmfmac || _doc_fail "brcmfmac not loaded" "mbp16-1 apply wifi" "mbp16-1 apply wifi"
    grep -q 'feature_disable=0x82000' /etc/modprobe.d/brcmfmac.conf 2>/dev/null || \
      _doc_fail "WPA workaround missing" "mbp16-1 apply wifi" "mbp16-1 apply wifi"
  fi

  # ── Power: dGPU pin, CPU daemon, fans
  section "Power" "Super menu only. Never DPM auto, TLP, or Omarchy stock 55–75 °C fans."
  subsection "dGPU:"
  if systemctl is-enabled mbp2019-amdgpu-power-prep.service >/dev/null 2>&1; then
    ok "Randy DPM oneshot (low at boot)"
  elif [[ $amd == "$AMD_DEVICE" ]]; then
    _doc_fail "Randy DPM oneshot not enabled" "mbp16-1 apply power" "mbp16-1 apply power"
  else
    info "Randy DPM oneshot skipped" "not a 5500M ${AMD_DEVICE}"
  fi

  subsection "CPU:"
  local powerd=0 conf=0 ac=0 turbo=0
  systemctl is-active mbp16-1-powerd.service >/dev/null 2>&1 && powerd=1
  [[ -f /etc/mbp16-1-powerd.conf ]] && conf=1
  [[ $(tr -d '\n' <"$HOME/.local/state/omarchy/powerprofiles/ac" 2>/dev/null) == balanced ]] && ac=1
  no_turbo=$(read_sys /sys/devices/system/cpu/intel_pstate/no_turbo)
  [[ $no_turbo == 0 ]] && turbo=1
  if [[ $no_turbo == 1 ]]; then
    _doc_fail "no_turbo=1" "this recipe keeps turbo on"
  fi
  if ((powerd && conf && ac && turbo)); then
    ok "powerd  ·  AC balanced  ·  turbo on"
  else
    if systemctl is-enabled mbp16-1-powerd.service >/dev/null 2>&1 && ((powerd == 0)); then
      _doc_fail "powerd enabled but not running" "mbp16-1 apply power" "mbp16-1 apply power"
    elif ((powerd == 0)); then
      info "powerd not running" "mbp16-1 apply power"
      ui_next "mbp16-1 apply power"
    fi
    ((conf)) || {
      info "powerd conf missing" "mbp16-1 apply power"
      ui_next "mbp16-1 apply power"
    }
    ((ac)) || info "AC Super is not balanced" "omarchy-powerprofiles-set ac balanced"
    ((turbo)) || true
  fi

  subsection "Fans:"
  local fans=0 linear=0 temps=0 running=0
  grep -q '\[Fan1\]' /etc/t2fand.conf 2>/dev/null && grep -q '\[Fan2\]' /etc/t2fand.conf 2>/dev/null && fans=1
  grep -q 'speed_curve=linear' /etc/t2fand.conf 2>/dev/null && linear=1
  grep -q 'low_temp=40' /etc/t2fand.conf 2>/dev/null && grep -q 'high_temp=85' /etc/t2fand.conf 2>/dev/null && temps=1
  systemctl is-active t2fanrd.service >/dev/null 2>&1 && running=1
  if ((fans && linear && temps && running)); then
    ok "t2fanrd  ·  linear 40–85 °C  ·  Fan1+Fan2"
  else
    ((running)) || _doc_fail "t2fanrd not running" "mbp16-1 apply fans" "mbp16-1 apply fans"
    ((fans)) || _doc_fail "t2fand.conf missing Fan1/Fan2" "mbp16-1 apply fans" "mbp16-1 apply fans"
    ((linear)) || _doc_fail "fan curve is not linear" "mbp16-1 apply fans" "mbp16-1 apply fans"
    if ((temps == 0)); then
      if grep -q 'low_temp=55' /etc/t2fand.conf 2>/dev/null && grep -q 'high_temp=75' /etc/t2fand.conf 2>/dev/null; then
        _doc_fail "Fans are Omarchy stock 55–75 °C" "mbp16-1 apply fans" "mbp16-1 apply fans"
      else
        info "Fan temps are not 40–85 °C" "mbp16-1 apply fans"
      fi
    fi
  fi

  section "Input" "Keyboard files: Apple ISO French only."
  local pad=0 kb=0 greeter=0
  file_has "$HOME/.config/hypr/input.lua" 'sensitivity = 0.25' && pad=1
  iso=$(read_sys /sys/module/hid_apple/parameters/iso_layout)
  if _doc_fr_mac_files; then
    [[ $iso == 1 ]] && kb=1
  else
    kb=1 # skipped layout is fine
  fi
  if [[ -f /etc/sddm/hyprland-mbp16-1.lua ]] &&
    grep -q 'hyprland-mbp16-1.lua' /etc/sddm.conf.d/20-mbp16-1-greeter.conf 2>/dev/null; then
    greeter=1
  elif [[ -f /etc/sddm/hyprland-mbp16-1-nolayout.lua ]] &&
    grep -q 'hyprland-mbp16-1-nolayout.lua' /etc/sddm.conf.d/20-mbp16-1-greeter-nolayout.conf 2>/dev/null; then
    greeter=1
  fi
  if ((pad && kb && greeter)); then
    if _doc_fr_mac_files; then
      ok "Trackpad 0.25  ·  ISO French  ·  SDDM greeter"
    else
      ok "Trackpad 0.25  ·  keyboard skipped  ·  SDDM greeter"
    fi
  else
    ((pad)) || {
      info "Trackpad sensitivity is not 0.25" "mbp16-1 apply input"
      ui_next "mbp16-1 apply input"
    }
    if _doc_fr_mac_files && [[ $iso != 1 ]]; then
      info "iso_layout=${iso:-unset} (want 1)" "mbp16-1 apply input --layout fr-mac"
      ui_next "mbp16-1 apply input --layout fr-mac"
    fi
    ((greeter)) || {
      info "SDDM greeter override missing" "mbp16-1 apply input"
      ui_next "mbp16-1 apply input"
    }
  fi

  section "Touch ID" "T2 SEP. Not Omarchy Fingerprint. Never unload transport."
  local ncm=0 bl=0 userspace=0
  if module_loaded cdc_ncm || grep -Rsq 'PRODUCT=5ac/8233' /sys/bus/usb/devices/*/uevent 2>/dev/null; then
    ncm=1
  fi
  grep -q 'blacklist t2_sep_transport' /etc/modprobe.d/t2-sep-transport.conf 2>/dev/null && bl=1
  if [[ -e /opt/t2-touchid ]] || command -v t2-keybag-unlock >/dev/null 2>&1; then
    userspace=1
  fi
  if ((ncm && bl && userspace)); then
    if module_loaded t2_sep_transport; then
      ok "NCM  ·  transport up  ·  userspace"
    else
      ok "NCM  ·  autoload blacklisted  ·  userspace"
    fi
  elif ((userspace == 0 && ncm == 0 && bl == 0)); then
    info "Not installed yet" "mbp16-1 apply touchid"
    ui_next "mbp16-1 apply touchid"
  else
    ((ncm)) || info "T2 NCM not seen" "needed for Touch ID"
    ((bl)) || info "Transport blacklist missing" "mbp16-1 apply touchid"
    ((userspace)) || info "t2-touchid missing" "mbp16-1 apply touchid"
    if module_loaded t2_sep_transport; then
      hint "transport loaded — do not unload, do not start a second one this boot"
    fi
  fi
  if [[ ! -d /usr/lib/modules/$(uname -r)/build ]]; then
    info "Headers missing for this boot" "needed to compile t2_sep_transport"
  fi
  if ! have_pkg fprintd && ! have_cmd fprintd-verify; then
    info "fprintd missing" "mbp16-1 deps touchid"
    ui_next "mbp16-1 deps touchid"
  fi
  if systemctl is-enabled mbp16-1-lock-rearm.service >/dev/null 2>&1; then
    ok "lock rearm after s2idle"
  elif [[ -x $HOME/.local/bin/mbp16-1-lock-rearm ]]; then
    info "lock rearm helper without sleep unit" "mbp16-1 apply sleep"
  fi

  ui_summary
  return "$rc"
}

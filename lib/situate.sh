# Interactive checks / questions for apply. Sourced from bin/mbp16-1.

APPLY_CONFIG="${XDG_STATE_HOME:-$HOME/.local/state}/mbp16-1/apply.conf"
APPLY_BUNDLE=0
APPLY_SETUP=0
LAYOUT_RESOLVED=0
EXTERNAL_RESOLVED=0
PROMPT_IN=
PROMPT_OUT=

# EXTERNAL: ask | yes | no
# EXTERNAL_DESC / EXTERNAL_MODE / EXTERNAL_SCALE / EXTERNAL_POS
EXTERNAL=${EXTERNAL:-ask}
EXTERNAL_DESC=${EXTERNAL_DESC:-}
EXTERNAL_MODE=${EXTERNAL_MODE:-preferred}
EXTERNAL_SCALE=${EXTERNAL_SCALE:-auto}
EXTERNAL_POS=${EXTERNAL_POS:-auto-center-up}

prompt_bind_tty() {
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    PROMPT_IN=/dev/tty
    PROMPT_OUT=/dev/tty
  elif [[ -t 0 && -t 1 ]]; then
    PROMPT_IN=/dev/stdin
    PROMPT_OUT=/dev/stdout
  else
    PROMPT_IN=
    PROMPT_OUT=
  fi
}

prompt_can_ask() {
  prompt_bind_tty
  [[ -n $PROMPT_IN ]]
}

# ask_yn "question" y|n
# default is used for empty reply, --yes, and dry-run without a TTY.
ask_yn() {
  local q=$1 default=${2:-n} reply hint
  if ((ASSUME_YES)); then
    log "assuming ${default}" "$q"
    [[ $default == [yY] ]]
    return
  fi
  if ((DRY_RUN)) && ! prompt_can_ask; then
    log "dry-run, no TTY: assuming ${default}" "$q"
    [[ $default == [yY] ]]
    return
  fi
  if ! prompt_can_ask; then
    die "need a TTY to ask: $q" \
      "Re-run in a terminal, or pass --yes plus --layout / --external (see mbp16-1 help)."
  fi
  if [[ $default == [yY] ]]; then
    hint='[Y/n]'
  else
    hint='[y/N]'
  fi
  printf '\n  %s?%s  %s %s ' "$C_BOLD$C_CYAN" "$C_RESET" "$q" "$hint" >"$PROMPT_OUT"
  read -r reply <"$PROMPT_IN" || die "no answer (EOF)"
  reply=${reply:-$default}
  case $(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]') in
    y|yes) return 0 ;;
    n|no) return 1 ;;
    *)
      warn "answer y or n"
      ask_yn "$q" "$default"
      return
      ;;
  esac
}

# ask_line "question" "default"
ask_line() {
  local q=$1 default=${2:-} reply
  if ((ASSUME_YES)); then
    printf '%s\n' "$default"
    return 0
  fi
  if ! prompt_can_ask; then
    if [[ -n $default ]]; then
      printf '%s\n' "$default"
      return 0
    fi
    die "need a TTY to ask: $q" "Pass --external-desc 'Monitor Name' or --yes with a saved config."
  fi
  if [[ -n $default ]]; then
    printf '\n  %s?%s  %s\n      %sdefault:%s %s\n  %s→%s ' \
      "$C_BOLD$C_CYAN" "$C_RESET" "$q" "$C_DIM" "$C_RESET" "$default" \
      "$C_CYAN" "$C_RESET" >"$PROMPT_OUT"
  else
    printf '\n  %s?%s  %s\n  %s→%s ' \
      "$C_BOLD$C_CYAN" "$C_RESET" "$q" "$C_CYAN" "$C_RESET" >"$PROMPT_OUT"
  fi
  read -r reply <"$PROMPT_IN" || die "no answer (EOF)"
  printf '%s\n' "${reply:-$default}"
}

# Print instructions, require an explicit yes (unless --yes).
confirm_ready() {
  local title=$1
  shift
  section "$title" "Do these on the machine, then confirm. --yes skips the wait (not the checks)."
  local line
  for line in "$@"; do
    hint "$line"
  done
  if ((DRY_RUN)); then
    log "dry-run: would wait for confirmation"
    return 0
  fi
  if ((ASSUME_YES)); then
    log "assuming those steps are done (--yes)"
    return 0
  fi
  if ask_yn "Done — continue?" n; then
    ok "confirmed"
    return 0
  fi
  die "stopped until those steps are done" "Re-run the same command when they are."
}

# One gate: type y (default n). Machine checks still run. --yes skips the wait.
require_yes() {
  local q=$1 hint=${2:-Re-run the same command when that is true.}
  if ((DRY_RUN)); then
    log "dry-run: would ask" "$q"
    return 0
  fi
  if ((ASSUME_YES)); then
    log "assuming yes (--yes)" "$q"
    return 0
  fi
  if ask_yn "$q" n; then
    ok "yes" "$q"
    return 0
  fi
  die "stopped" "$hint"
}

lua_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

save_apply_config() {
  ((DRY_RUN)) && return 0
  mkdir -p "$(dirname "$APPLY_CONFIG")"
  {
    printf 'LAYOUT=%q\n' "$LAYOUT"
    printf 'EXTERNAL=%q\n' "$EXTERNAL"
    printf 'EXTERNAL_DESC=%q\n' "$EXTERNAL_DESC"
    printf 'EXTERNAL_MODE=%q\n' "$EXTERNAL_MODE"
    printf 'EXTERNAL_SCALE=%q\n' "$EXTERNAL_SCALE"
    printf 'EXTERNAL_POS=%q\n' "$EXTERNAL_POS"
  } >"$APPLY_CONFIG"
  log "saved answers" "$APPLY_CONFIG"
}

amd_device_id() {
  read_sys "/sys/bus/pci/devices/${AMD_PCI}/device"
}

intel_vendor_id() {
  read_sys "/sys/bus/pci/devices/${INTEL_PCI}/vendor"
}

dpm_level() {
  read_sys "/sys/bus/pci/devices/${AMD_PCI}/power_dpm_force_performance_level"
}

amdgpu_blacklisted() {
  local c
  c=$(tr -d '\n' </proc/cmdline 2>/dev/null || true)
  [[ $c == *module_blacklist=amdgpu* || $c == *modprobe.blacklist=amdgpu* ]]
}

drm_dp_connected() {
  local f
  for f in /sys/class/drm/card*-DP-*/status /sys/class/drm/card*-HDMI-A-*/status; do
    [[ -r $f ]] || continue
    [[ $(tr -d '\n' <"$f") == connected ]] && return 0
  done
  return 1
}

ac_is_online() {
  local f
  for f in /sys/class/power_supply/*/online; do
    [[ -r $f ]] || continue
    [[ $(tr -d '\n' <"$f") == 1 ]] && return 0
  done
  return 1
}

hypr_monitor_descs() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0
  hyprctl monitors all -j 2>/dev/null | jq -r '
    .[]
    | select((.description // "") != "")
    | .description
  ' || true
}

detect_layout() {
  if [[ -f ${XDG_CONFIG_HOME:-$HOME/.config}/hypr/input.lua ]] &&
    grep -q 'kb_layout = "fr"' "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/input.lua" &&
    grep -q 'kb_variant = "mac"' "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/input.lua"; then
    printf '%s\n' fr-mac
    return
  fi
  if grep -q '^KEYMAP=mac-fr' /etc/vconsole.conf 2>/dev/null; then
    printf '%s\n' fr-mac
    return
  fi
  if [[ $(read_sys /sys/module/hid_apple/parameters/iso_layout) == 1 ]]; then
    printf '%s\n' fr-mac
    return
  fi
  printf '%s\n' unknown
}

detect_external_desc() {
  local d
  while IFS= read -r d; do
    [[ -n $d ]] || continue
    [[ $d == *Color\ LCD* ]] && continue
    printf '%s\n' "$d"
    return 0
  done < <(hypr_monitor_descs)
  return 1
}

situate_pci() {
  section "Pre-check — PCI" \
    "Intel at 00:02.0 is the lid. AMD at 03:00.0 is USB-C DP. Measure on this machine."
  local intel amd
  intel=$(intel_vendor_id)
  amd=$(amd_device_id)
  if [[ $intel == 0x8086 ]]; then
    ok "Intel at ${INTEL_PCI}"
  else
    die "Intel not at ${INTEL_PCI} (vendor=${intel:-missing})" \
      "This recipe expects UHD 630 there. Pass --i-know only if you measured the same layout."
  fi
  if [[ $amd == "$AMD_DEVICE" ]]; then
    ok "AMD 5500M ${AMD_DEVICE} at ${AMD_PCI}"
  elif [[ -n $amd ]]; then
    warn "AMD at ${AMD_PCI} is ${amd}" "Randy DPM installer wants ${AMD_DEVICE} (5500M). Power step will skip it."
  else
    die "no AMD at ${AMD_PCI}" "Is this a 16,1 with dGPU? USB-C DP will not work without it."
  fi
}

precheck_gpu() {
  require_16_1
  is_linux || die "apply gpu is Linux-only"
  situate_pci
  if [[ $(dpm_level) == auto ]]; then
    die "AMD DPM is auto" "Do not continue. Pin low with Randy’s service later (never write auto)."
  fi
  if amdgpu_blacklisted; then
    warn "cmdline has module_blacklist=amdgpu" \
      "That is the black-panel workaround. Files still apply. Next reboot must drop that token so AMD binds."
  fi
}

precheck_power() {
  require_16_1
  is_linux || die "apply power is Linux-only"
  if amdgpu_blacklisted; then
    die "amdgpu is blacklisted this boot" \
      "Reboot without module_blacklist=amdgpu, then retry apply power (DPM sysfs needs the driver)."
  fi
  if [[ -z $(dpm_level) ]]; then
    die "DPM sysfs missing — amdgpu not bound" \
      "Reboot without module_blacklist=amdgpu, confirm /dev/dri/amd-dgpu, then retry."
  fi
  if [[ $(dpm_level) == auto ]]; then
    die "AMD DPM is auto" "Do not continue. Never write auto on this topology."
  fi
  local amd
  amd=$(amd_device_id)
  if [[ $amd != "$AMD_DEVICE" ]]; then
    warn "skipping Randy DPM installer" "device ${amd:-missing} is not ${AMD_DEVICE} (5500M)"
    return 1
  fi
  return 0
}

precheck_kernel_build() {
  ensure_kernel_build_tools
  if ! ac_is_online; then
    warn "AC adapter does not look online" "First makepkg is 45–90 min — plug in."
    if ! ask_yn "Continue the kernel build on battery?" n; then
      die "plug in, then re-run this command"
    fi
  else
    ok "AC online"
  fi
  confirm_ready "Kernel build" \
    "Stay plugged in, lid open. Do not suspend, close the lid, or power off for 45–90 minutes." \
    "Stock linux-t2 stays installed (recovery only — do not suspend on it)." \
    "Unplug USB-C after this finishes, then reboot onto linux-t2-mbp161."
}

precheck_touchid() {
  local rc=0 running
  running=$(kernel_running_pkgbase)
  section "Touch ID gate" "Skip Omarchy Setup → Fingerprint. One transport start per boot. Never unload t2_sep_transport."
  if kernel_is_daily; then
    ok "running pkgbase is ${KERNEL_PKGBASE}" "this boot: $(uname -r)"
  else
    fail "running pkgbase is ${running}" \
      "s2idle on stock kills the 5500M SMU. Boot ${KERNEL_PKGBASE} first (identity is pkgbase, not a version string)."
    rc=1
  fi
  if [[ $(dpm_level) == low ]]; then
    ok "AMD DPM is low"
  else
    fail "AMD DPM is $(dpm_level:-missing)" "want low before talking to SEP"
    rc=1
  fi
  if module_loaded cdc_ncm || grep -Rsq 'PRODUCT=5ac/8233' /sys/bus/usb/devices/*/uevent 2>/dev/null; then
    ok "T2 NCM present"
  else
    fail "T2 NCM not seen" "ip -br link — need cdc_ncm on 05ac:8233, not wlan"
    rc=1
  fi
  if module_loaded t2_sep_transport; then
    warn "t2_sep_transport is already loaded" "do not start a second transport this boot"
  fi
  ((rc == 0)) || die "Touch ID gate failed" "Fix the red lines, then retry apply touchid."
}

# Resolve LAYOUT to fr-mac or skip. Idempotent in one process.
resolve_layout() {
  ((LAYOUT_RESOLVED)) && return 0
  if [[ $LAYOUT == fr-mac || $LAYOUT == skip ]]; then
    LAYOUT_RESOLVED=1
    log "keyboard layout  $LAYOUT" "from --layout / saved config"
    return 0
  fi

  section "Keyboard" \
    "Omarchy writes PC fr. Apple ISO French needs fr(mac) + hid_apple iso_layout=1. Other boards: skip (trackpad + DWT + greeter cursor only)."

  local detected default=n
  detected=$(detect_layout)
  case $detected in
    fr-mac)
      ok "detected Apple ISO French already configured"
      default=y
      ;;
    *)
      info "no fr(mac) config detected" "US / UK / ANSI / PC-fr should answer no"
      default=n
      ;;
  esac

  if ask_yn "Is the built-in keyboard Apple ISO French (Mac AZERTY — @ # <> match macOS)?" "$default"; then
    LAYOUT=fr-mac
  else
    LAYOUT=skip
  fi
  LAYOUT_RESOLVED=1
  log "keyboard layout  $LAYOUT"
  save_apply_config
}

resolve_external() {
  ((EXTERNAL_RESOLVED)) && return 0
  if [[ $EXTERNAL == no ]]; then
    EXTERNAL_RESOLVED=1
    log "external display  none" "lid only"
    return 0
  fi
  if [[ $EXTERNAL == yes && -n $EXTERNAL_DESC ]]; then
    EXTERNAL_RESOLVED=1
    log "external display  $EXTERNAL_DESC"
    return 0
  fi

  if ((ASSUME_YES)); then
    local detected=""
    if detected=$(detect_external_desc); then
      EXTERNAL=yes
      EXTERNAL_DESC=$detected
      if [[ $EXTERNAL_DESC == *LG*HDR*4K* ]]; then
        EXTERNAL_MODE=3840x2160@60
        EXTERNAL_SCALE=1.5
        EXTERNAL_POS=auto-center-up
      fi
      log "--yes: pin USB-C by Hyprland description" "$EXTERNAL_DESC"
    else
      EXTERNAL=no
      EXTERNAL_DESC=
      warn "--yes: no Hyprland external description — lid only" \
        "Pass --external-desc 'Make Model' if you have a USB-C panel."
    fi
    EXTERNAL_RESOLVED=1
    save_apply_config
    return 0
  fi

  section "USB-C display" \
    "DP is on AMD. Login unplugged; plug a left Thunderbolt 3 port after the lid is up. Pin by description, never eDP-*/DP-*."

  local detected="" default=n
  if detected=$(detect_external_desc); then
    ok "Hyprland sees: ${detected}"
    default=y
  else
    detected=
    info "no external description from hyprctl" "normal if you are lid-only, or Hyprland is not running"
  fi
  if drm_dp_connected; then
    warn "a DP/HDMI sink is connected right now" \
      "Starting Hyprland with AMD in Aqua and the cable already in can black the lid."
    default=y
  fi

  if [[ $EXTERNAL != yes ]] && ! ask_yn "Do you use a USB-C / Thunderbolt monitor with this Mac?" "$default"; then
    EXTERNAL=no
    EXTERNAL_DESC=
    EXTERNAL_RESOLVED=1
    log "external display  none"
    save_apply_config
    return 0
  fi

  EXTERNAL=yes
  if [[ -z $EXTERNAL_DESC ]]; then
    EXTERNAL_DESC=$(ask_line "hyprctl description of that panel (exact string)" "${detected:-LG Electronics LG HDR 4K}")
  fi
  [[ -n $EXTERNAL_DESC ]] || die "empty monitor description" "run: hyprctl monitors all   then re-run with --external-desc '...'"

  if [[ $EXTERNAL_DESC == *LG*HDR*4K* ]]; then
    EXTERNAL_MODE=${EXTERNAL_MODE:-3840x2160@60}
    EXTERNAL_SCALE=${EXTERNAL_SCALE:-1.5}
    EXTERNAL_POS=${EXTERNAL_POS:-auto-center-up}
    log "using LG HDR 4K recipe" "3840×2160@60, scale 1.5, above the lid"
  else
    if [[ $EXTERNAL_MODE == preferred ]]; then
      :
    fi
    EXTERNAL_MODE=${EXTERNAL_MODE:-preferred}
    EXTERNAL_SCALE=${EXTERNAL_SCALE:-1.5}
    EXTERNAL_POS=${EXTERNAL_POS:-auto-center-up}
    info "not the recipe LG — pinning by description" \
      "mode=${EXTERNAL_MODE}  scale=${EXTERNAL_SCALE}  position=${EXTERNAL_POS}  (edit monitors.lua later if needed)"
  fi

  if drm_dp_connected && ((APPLY_BUNDLE == 0)); then
    confirm_ready "Unplug before the next login" \
      "Unplug the USB-C monitor now if you will log out or reboot next." \
      "Plug it only after the lid (Apple Color LCD) is up." \
      "Never disable Color LCD by eDP-1 / eDP-2 name."
  fi

  EXTERNAL_RESOLVED=1
  log "external display  $EXTERNAL_DESC"
  save_apply_config
}

write_monitors_lua() {
  local dest="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/monitors.lua"
  local lid ext scale_lua tmp
  lid=$(lua_escape "Apple Computer Inc Color LCD")
  mkdir -p "$(dirname "$dest")"
  tmp=$(mktemp)
  cat >"$tmp" <<EOF
-- Generated by mbp16-1 apply display. Do NOT disable eDP-1 / eDP-2 by name.
-- Lid = Color LCD. Phantom eDP (empty description) is disabled by mbp16-1-hypr-outputs.

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = "auto"

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

hl.monitor({
  output = "desc:${lid}",
  mode = "3072x1920@60",
  position = "0x0",
  scale = 2,
})
EOF
  if [[ $EXTERNAL == yes && -n $EXTERNAL_DESC ]]; then
    ext=$(lua_escape "$EXTERNAL_DESC")
    if [[ $EXTERNAL_SCALE =~ ^[0-9.]+$ ]]; then
      scale_lua=$EXTERNAL_SCALE
    else
      scale_lua="\"$(lua_escape "$EXTERNAL_SCALE")\""
    fi
    cat >>"$tmp" <<EOF

hl.monitor({
  output = "desc:${ext}",
  mode = "${EXTERNAL_MODE}",
  position = "${EXTERNAL_POS}",
  scale = ${scale_lua},
})
EOF
  else
    cat >>"$tmp" <<'EOF'

-- No USB-C monitor pinned. Catch-all above puts the next head to the right.
EOF
  fi
  if [[ -f $dest ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    log "unchanged  $dest"
    return 0
  fi
  backup_if_exists "$dest"
  if ((DRY_RUN)); then
    rm -f "$tmp"
    log "would write  $dest" "external=${EXTERNAL:-no}"
    return 0
  fi
  install -D -m 0644 "$tmp" "$dest"
  rm -f "$tmp"
  log "wrote  $dest"
}

write_sleep_dropin() {
  local dest="$CACHE/generated/00-mbp16-1-sleep.conf"
  mkdir -p "$(dirname "$dest")"
  local extra=""
  if [[ $LAYOUT == fr-mac ]]; then
    extra=" hid_apple.iso_layout=1"
  fi
  cat >"$dest" <<EOF
# Generated by mbp16-1 apply sleep.
# Named 00- so this line stays last on the merged cmdline (later drop-ins prepend).
# Do not use KERNEL_CMDLINE[default]= — that wipes drop-ins.
KERNEL_CMDLINE[default]+=" mem_sleep_default=s2idle pcie_ports=compat${extra}"
EOF
  install_root_file "$dest" /etc/limine-entry-tool.d/00-mbp16-1-sleep.conf
}

install_sddm_greeter() {
  if [[ $LAYOUT == fr-mac ]]; then
    install_root_file "$FILES/etc/sddm/hyprland-mbp16-1.lua" /etc/sddm/hyprland-mbp16-1.lua
    install_root_file "$FILES/etc/sddm.conf.d/20-mbp16-1-greeter.conf" /etc/sddm.conf.d/20-mbp16-1-greeter.conf
  else
    install_root_file "$FILES/etc/sddm/hyprland-mbp16-1-nolayout.lua" /etc/sddm/hyprland-mbp16-1-nolayout.lua
    install_root_file "$FILES/etc/sddm.conf.d/20-mbp16-1-greeter-nolayout.conf" /etc/sddm.conf.d/20-mbp16-1-greeter-nolayout.conf
  fi
}

maybe_reuse_config() {
  [[ -f $APPLY_CONFIG ]] || return 0
  [[ $LAYOUT == ask && $EXTERNAL == ask ]] || return 0
  section "Saved answers" "$APPLY_CONFIG"
  # shellcheck disable=SC1090
  source "$APPLY_CONFIG"
  hint "keyboard  ${LAYOUT}    USB-C  ${EXTERNAL}${EXTERNAL_DESC:+  ($EXTERNAL_DESC)}"
  if ((ASSUME_YES)); then
    LAYOUT_RESOLVED=1
    EXTERNAL_RESOLVED=1
    log "reusing saved answers (--yes)"
    return 0
  fi
  if ask_yn "Reuse these?" y; then
    LAYOUT_RESOLVED=1
    EXTERNAL_RESOLVED=1
    ok "reusing saved answers"
  else
    LAYOUT=ask
    EXTERNAL=ask
    EXTERNAL_DESC=
    LAYOUT_RESOLVED=0
    EXTERNAL_RESOLVED=0
  fi
}

situate_desktop() {
  maybe_reuse_config
  situate_pci
  resolve_layout
  resolve_external
  save_apply_config
  if ((APPLY_SETUP)); then
    if drm_dp_connected; then
      require_yes "USB-C is connected — I will unplug it before the next login (start lid-only)" \
        "Unplug the monitor, then re-run setup. Next graphical session must start lid-only."
    fi
    return 0
  fi
  if drm_dp_connected; then
    confirm_ready "Before writing desktop files" \
      "Unplug the USB-C monitor if it is in (next graphical session must start lid-only)." \
      "Keep a wired USB keyboard on the Mac." \
      "Do not run Trigger → Hybrid GPU / supergfxctl. Do not write DPM auto."
  else
    confirm_ready "Before writing desktop files" \
      "Keep a wired USB keyboard on the Mac." \
      "Next reboot: no module_blacklist=amdgpu, USB-C unplugged." \
      "Do not run Trigger → Hybrid GPU / supergfxctl. Do not write DPM auto."
  fi
}

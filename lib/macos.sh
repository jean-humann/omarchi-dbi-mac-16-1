# macOS Phase A. Sourced from bin/mbp16-1.
# `macos` maps APFS + two USB disks (TTY), then shrink → export → ISO → flash.
# Long jobs stay serial on the internal SSD. Never dd disk0.

MACOS_INSTALLER=${MACOS_INSTALLER:-}
MACOS_PRIVATE=${MACOS_PRIVATE:-}
MACOS_ISO=${MACOS_ISO:-}
MACOS_ISO_PATH=
MACOS_PRIVATE_MOUNT=
MACOS_USB_DISKS=()
MACOS_CONTAINER=${MACOS_CONTAINER:-${MBP16_1_APFS_CONTAINER:-}}
MACOS_FREE=${MACOS_FREE:-}
MACOS_KEEP=${MACOS_KEEP:-}
MACOS_SHRINK_APPLY=${MACOS_SHRINK_APPLY:-0}
MACOS_SHRINK_SKIP=0
MACOS_CONTAINER_MAPPED=0
MACOS_T2_SECURE=unknown
MACOS_T2_EXTERNAL=unknown

# T2 Startup Security Utility lives in Recovery — we cannot set it from macOS.
# We can often read it: mdmclient QuerySecurityInfo (both knobs) and
# NVRAM AppleSecureBootPolicy (Secure Boot only: %00 off / %01 medium / %02 full).
# Never print the raw QuerySecurityInfo blob (serials / FileVault).
# Parse with perl (ships on macOS). Do not call python3 — the CLT stub can pop a GUI.
_macos_parse_t2_boot_policy() {
  command -v perl >/dev/null 2>&1 || return 0
  perl -0777 -ne '
    my ($s, $e);
    $s = lc $1 if /<key>SecureBootLevel<\/key>\s*<string>([^<]+)<\/string>/i
               or /SecureBootLevel\s*=\s*"?([A-Za-z]+)"?/;
    $e = lc $1 if /<key>ExternalBootLevel<\/key>\s*<string>([^<]+)<\/string>/i
               or /ExternalBootLevel\s*=\s*"?([A-Za-z]+)"?/;
    print "secure=$s\n" if $s;
    print "external=$e\n" if $e;
  '
}

_macos_read_t2_boot_policy() {
  MACOS_T2_SECURE=unknown
  MACOS_T2_EXTERNAL=unknown
  local nv parsed blob line

  if [[ -x /usr/libexec/mdmclient ]]; then
    blob=$(/usr/libexec/mdmclient QuerySecurityInfo 2>/dev/null || true)
    parsed=$(printf '%s' "$blob" | _macos_parse_t2_boot_policy)
    unset blob
    while IFS= read -r line; do
      case $line in
        secure=off|secure=medium|secure=full) MACOS_T2_SECURE=${line#secure=} ;;
        secure=notsupported) MACOS_T2_SECURE=unknown ;;
        external=allowed|external=disallowed) MACOS_T2_EXTERNAL=${line#external=} ;;
        external=notsupported) MACOS_T2_EXTERNAL=unknown ;;
      esac
    done <<<"$parsed"
  fi

  if [[ $MACOS_T2_SECURE == unknown ]] && command -v nvram >/dev/null 2>&1; then
    nv=$(nvram 94b73556-2197-4702-82a8-3e1337dafbfb:AppleSecureBootPolicy 2>/dev/null || \
         nvram 94B73556-2197-4702-82A8-3E1337DAFBFB:AppleSecureBootPolicy 2>/dev/null || true)
    case $nv in
      *%00*) MACOS_T2_SECURE=off ;;
      *%01*) MACOS_T2_SECURE=medium ;;
      *%02*) MACOS_T2_SECURE=full ;;
    esac
  fi
}

_macos_t2_recovery_hint() {
  printf '%s' "Command-R (internal recoveryOS) → Utilities → Startup Security Utility → No Security + allow external media, then restart into macOS."
}

# 0 = both knobs look right. 1 = at least one is wrong (caller should stop).
# 2 = could not read one or both (caller should still ask the human).
_macos_t2_boot_policy_state() {
  _macos_read_t2_boot_policy
  if [[ $MACOS_T2_SECURE == off && $MACOS_T2_EXTERNAL == allowed ]]; then
    return 0
  fi
  if [[ $MACOS_T2_SECURE == full || $MACOS_T2_SECURE == medium || $MACOS_T2_EXTERNAL == disallowed ]]; then
    return 1
  fi
  return 2
}

_macos_require_t2_boot_policy() {
  local st=0
  section "Startup Security" \
    "T2 policy. macos cannot set this — Recovery only. This check reads it from macOS when Apple exposes it."
  _macos_t2_boot_policy_state || st=$?
  case $st in
    0)
      ok "No Security  ·  external media allowed"
      return 0
      ;;
    1)
      die "Startup Security is not ready for Omarchy" \
        "Secure Boot=${MACOS_T2_SECURE} (want off / No Security). External=${MACOS_T2_EXTERNAL} (want allowed). $(_macos_t2_recovery_hint)"
      ;;
    *)
      [[ $MACOS_T2_SECURE == off ]] && ok "Secure Boot is No Security" || \
        info "Secure Boot unread" "nvram AppleSecureBootPolicy / mdmclient did not report it"
      [[ $MACOS_T2_EXTERNAL == allowed ]] && ok "external media allowed" || \
        info "External boot unread" "Apple does not always expose Allowed Boot Media to a booted session"
      return 2
      ;;
  esac
}

_macos_on_ac() {
  local ps
  command -v pmset >/dev/null 2>&1 || return 1
  ps=$(pmset -g ps 2>/dev/null | head -n 1 || true)
  case $ps in
    *'AC Power'*) return 0 ;;
    *) return 1 ;;
  esac
}

# enrolled | empty | unknown — never print bioutil (account names).
_macos_touchid_state() {
  local out
  if ! command -v bioutil >/dev/null 2>&1; then
    printf 'unknown\n'
    return 0
  fi
  out=$(bioutil -c 2>/dev/null || true)
  if [[ -z $out ]]; then
    printf 'unknown\n'
    return 0
  fi
  if printf '%s' "$out" | grep -Eqi 'Fingerprint:[[:space:]]*0([^0-9]|$)|0[[:space:]]+fingerprints?|no[[:space:]].*fingerprint'; then
    printf 'empty\n'
    return 0
  fi
  if printf '%s' "$out" | grep -Eqi 'Fingerprint:[[:space:]]*[1-9]|[1-9][0-9]*[[:space:]]+fingerprints?'; then
    printf 'enrolled\n'
    return 0
  fi
  printf 'unknown\n'
}

_macos_easy_preflight() {
  local rec=0 usb_n tid
  section "Checks" "Machine facts first. --yes does not skip these."
  ok "model" "$(product_name)"
  rec=0
  _macos_require_t2_boot_policy || rec=$?
  if _macos_on_ac; then
    ok "power" "AC"
  else
    info "power" "battery — shrink often takes 20–40 min"
  fi
  tid=$(_macos_touchid_state)
  case $tid in
    enrolled) ok "Touch ID" "prints enrolled  ·  id -u $(id -u)" ;;
    empty)
      die "no Touch ID prints enrolled" \
        "System Settings → Touch ID, enroll a finger, note id -u, then re-run macos."
      ;;
    *) info "Touch ID" "could not read enrollments — you will confirm next" ;;
  esac
  _macos_collect_usb
  usb_n=${#MACOS_USB_DISKS[@]}
  if ((usb_n < 2)); then
    die "need two USB whole disks (saw ${usb_n})" \
      "Installer ≥8 GB (will be FULLY ERASED) + private stick for keybags + this toolbox. A keyboard does not count."
  fi
  ok "USB disks" "${usb_n}  (${MACOS_USB_DISKS[*]})"

  section "Confirm each" "Default is no. Type y only if that line is true. --yes skips these waits, not the checks above."
  require_yes "This Mac is backed up (Time Machine or a clone)" \
    "Dual-boot can go wrong. Backup first, then re-run macos."
  if [[ $tid != enrolled ]]; then
    require_yes "Touch ID is enrolled in macOS and a finger works at the login prompt" \
      "System Settings → Touch ID, note id -u, then re-run macos."
  fi
  if ((rec != 0)); then
    require_yes "Recovery Startup Security Utility is No Security AND allow booting from external media" \
      "$(_macos_t2_recovery_hint)"
  fi
  require_yes "A wired USB keyboard is plugged into the Mac, lid is open" \
    "Need it for Recovery, LUKS, Limine, and a black lid. Plug it into the Mac, not only a dock."
  if ! _macos_on_ac; then
    require_yes "Continue the shrink on battery (20–40 min; do not sleep or close the lid)" \
      "Plug in AC, then re-run macos."
  fi
}

_macos_need_darwin() {
  is_darwin || die "$1 is for 16,1 macOS (got $(uname -s))" \
    "Run this on the Mac. A USB keyboard does not count as a disk."
  require_16_1
  command -v diskutil >/dev/null || die "diskutil missing"
}

_macos_norm_disk() {
  local s=$1
  s=${s#/dev/}
  case $s in
    rdisk[0-9]*) s=disk${s#rdisk} ;;
  esac
  case $s in
    disk[0-9]|disk[0-9][0-9]|disk[0-9][0-9][0-9])
      printf '%s\n' "$s"
      ;;
    disk[0-9]*s*)
      die "$1 is a partition" "pass the whole disk (diskN), not a slice"
      ;;
    *)
      die "not a whole-disk identifier: $1" "example: disk2"
      ;;
  esac
}

_macos_diskutil_val() {
  local disk=$1 want=$2
  diskutil info "$disk" | awk -F ':' -v want="$want" '
    {
      key=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key == want) {
        val=$0
        sub(/^[^:]+:[[:space:]]*/, "", val)
        print val
        exit
      }
    }
  '
}

_macos_disk_bytes() {
  local line
  line=$(_macos_diskutil_val "$1" "Disk Size")
  printf '%s\n' "$line" | sed -n 's/.*(\([0-9][0-9]*\) Bytes).*/\1/p' | head -n 1
}

_macos_file_bytes() {
  if stat -f%z "$1" >/dev/null 2>&1; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

_macos_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    die "need shasum or sha256sum"
  fi
}

_macos_collect_usb() {
  local id proto internal
  MACOS_USB_DISKS=()
  while IFS= read -r id; do
    [[ $id == disk[0-9]* ]] || continue
    case $id in
      disk[0-9]|disk[0-9][0-9]|disk[0-9][0-9][0-9]) ;;
      *) continue ;;
    esac
    [[ $id != disk0 ]] || continue
    internal=$(_macos_diskutil_val "$id" Internal)
    proto=$(_macos_diskutil_val "$id" Protocol)
    [[ $internal == No ]] || continue
    [[ $proto == USB ]] || continue
    MACOS_USB_DISKS+=("$id")
  done < <(diskutil list external physical 2>/dev/null | awk '
    /^\/dev\/disk[0-9]+/ {
      gsub(/^\/dev\//, "", $1)
      gsub(/:.*/, "", $1)
      print $1
    }
  ')
}

_macos_stick_role() {
  local list
  list=$(diskutil list "$1" 2>/dev/null || true)
  if printf '%s\n' "$list" | grep -qiE 'OMARCHY|ARCHISO|ISO9660'; then
    printf 'installer\n'
  elif printf '%s\n' "$list" | grep -qiE 'keybag|catacomb|t2-touchid|KEYBAGS'; then
    printf 'private\n'
  else
    printf 'unknown\n'
  fi
}

_macos_stick_volumes() {
  local line out=
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    [[ -n $out ]] && out+='; '
    out+=$line
  done < <(diskutil list "$1" 2>/dev/null | awk '
    $NF ~ /^disk[0-9]+s[0-9]+$/ {
      $NF=""
      sub(/[[:space:]]+$/, "")
      gsub(/^[[:space:]]+/, "")
      print
    }
  ')
  printf '%s\n' "$out"
}

_macos_describe() {
  local disk=$1 size media vols role
  size=$(_macos_diskutil_val "$disk" "Disk Size")
  media=$(_macos_diskutil_val "$disk" "Device / Media Name")
  vols=$(_macos_stick_volumes "$disk")
  role=$(_macos_stick_role "$disk")
  printf '%s  %s  %s%s  (%s)\n' "$disk" "$size" "$media" "${vols:+  ·  $vols}" "$role"
}

_macos_human_gb() {
  awk -v b="${1:-0}" 'BEGIN { printf "%.1f GB", b/1e9 }'
}

_macos_lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit (a+0 < b+0) ? 0 : 1 }'; }
_macos_ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit (a+0 >= b+0) ? 0 : 1 }'; }
_macos_sub() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.0f", a-b }'; }
_macos_add() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.0f", a+b }'; }

_macos_parse_size_to_bytes() {
  local s n u
  s=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ,')
  [[ -n $s ]] || die "empty size" "examples: 80g  360g  32g"
  if [[ $s =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$s"
    return 0
  fi
  n=$(printf '%s' "$s" | sed 's/[^0-9.].*//')
  u=$(printf '%s' "$s" | sed 's/^[0-9.]*//')
  [[ -n $n ]] || die "bad size $1" "examples: 80g  360g  32g"
  case $u in
    ''|b) awk -v n="$n" 'BEGIN { printf "%.0f", n }' ;;
    k|kb) awk -v n="$n" 'BEGIN { printf "%.0f", n*1e3 }' ;;
    m|mb) awk -v n="$n" 'BEGIN { printf "%.0f", n*1e6 }' ;;
    g|gb) awk -v n="$n" 'BEGIN { printf "%.0f", n*1e9 }' ;;
    t|tb) awk -v n="$n" 'BEGIN { printf "%.0f", n*1e12 }' ;;
    gi|gib) awk -v n="$n" 'BEGIN { printf "%.0f", n*1024*1024*1024 }' ;;
    *) die "bad size $1" "examples: 80g  360g  32g" ;;
  esac
}

_macos_norm_store() {
  local s=$1
  s=${s#/dev/}
  if [[ $s =~ ^disk[0-9]+$ ]]; then
    die "$1 is a whole disk" "pass the APFS physical store (usually disk0s2), not $s"
  fi
  if [[ $s =~ ^disk[0-9]+s[0-9]+$ ]]; then
    printf '%s\n' "$s"
    return 0
  fi
  die "not an APFS store identifier: $1" "example: disk0s2"
}

_macos_whole_from_store() {
  local s=$1
  s=${s#/dev/}
  if [[ $s =~ ^(disk[0-9]+)s[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  die "not an APFS store: $1"
}

_macos_apfs_limit_bytes() {
  local container=$1 needle=$2
  diskutil apfs resizeContainer "$container" limits 2>/dev/null | awk -v w="$needle" '
    index($0, w) {
      if (match($0, /\(([0-9]+) Bytes\)/)) {
        print substr($0, RSTART+1, RLENGTH-8)
        exit
      }
    }
  '
}

_macos_existing_free_bytes() {
  local whole=$1 n
  n=$(diskutil list "$whole" 2>/dev/null | awk '
    /free space/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9.]+$/ && $(i+1) ~ /^GB/) { printf "%.0f\n", $i * 1e9; exit }
        if ($i ~ /^[0-9.]+$/ && $(i+1) ~ /^MB/) { printf "%.0f\n", $i * 1e6; exit }
        if ($i ~ /^[0-9.]+$/ && $(i+1) ~ /^TB/) { printf "%.0f\n", $i * 1e12; exit }
      }
    }
  ')
  printf '%s\n' "${n:-0}"
}

_macos_find_apfs_stores() {
  local id proto internal
  while IFS= read -r id; do
    [[ -n $id ]] || continue
    internal=$(_macos_diskutil_val "$id" Internal)
    proto=$(_macos_diskutil_val "$id" Protocol)
    [[ $internal == Yes ]] || continue
    [[ $proto != USB ]] || continue
    printf '%s\n' "$id"
  done < <(diskutil list internal physical 2>/dev/null | awk '
    /Apple_APFS/ && $NF ~ /^disk[0-9]+s[0-9]+$/ { print $NF }
  ')
}

_macos_confirm_store() {
  local want=$1 prompt=$2 got
  if ((ASSUME_YES)); then
    log "assuming $want (--yes)" "$prompt"
    return 0
  fi
  got=$(ask_line "$prompt" "")
  got=$(_macos_norm_store "$got")
  [[ $got == "$want" ]] || die "typed $got, wanted $want" "that is the APFS store to shrink. Re-run."
}

_macos_disk_installer_fit() {
  # stdout: ok | tight | small | unknown
  local bytes iso min
  bytes=$(_macos_disk_bytes "$1")
  iso=${OMARCHY_ISO_BYTES:-6260654080}
  min=${MACOS_INSTALLER_MIN_BYTES:-8000000000}
  if [[ -z $bytes || $bytes -lt 1 ]]; then
    printf 'unknown\n'
    return 0
  fi
  if [[ $bytes -lt $iso ]]; then
    printf 'small\n'
  elif [[ $bytes -lt $min ]]; then
    printf 'tight\n'
  else
    printf 'ok\n'
  fi
}

_macos_assert_installer_size() {
  local disk=$1 bytes iso min
  bytes=$(_macos_disk_bytes "$disk")
  iso=${OMARCHY_ISO_BYTES:-6260654080}
  min=${MACOS_INSTALLER_MIN_BYTES:-8000000000}
  [[ -n $bytes ]] || die "cannot read size of $disk"
  if [[ $bytes -lt $iso ]]; then
    die "$disk is too small for the Omarchy ${OMARCHY_ISO_VERSION} ISO" \
      "$(_macos_human_gb "$bytes") stick, ISO is $(_macos_human_gb "$iso"). Use an 8 GB or larger USB stick."
  fi
  if [[ $bytes -lt $min ]]; then
    warn "$disk is $(_macos_human_gb "$bytes") — tight" \
      "ISO is $(_macos_human_gb "$iso"). Prefer 8 GB or larger."
  else
    ok "installer size" "$disk  $(_macos_human_gb "$bytes")  (request ≥8 GB; ISO ~6.3 GB)"
  fi
}

_macos_assert_usb() {
  local disk=$1
  local internal proto
  [[ $disk != disk0 ]] || die "refusing disk0" "that is the internal SSD"
  internal=$(_macos_diskutil_val "$disk" Internal)
  proto=$(_macos_diskutil_val "$disk" Protocol)
  [[ $internal == No ]] || die "$disk is internal" "refusing to write the ISO or keybags there"
  [[ $proto == USB ]] || die "$disk protocol is ${proto:-unknown}" "want a USB whole disk"
}

_macos_print_usb() {
  local i n id fit extra
  n=${#MACOS_USB_DISKS[@]}
  section "USB disks" "Installer stick: ≥8 GB (ISO ~6.3 GB). Flashing ERASES ALL DATA on that disk. A keyboard does not count."
  hint "Private stick is not wiped by dd. Never pick the same disk for both roles."
  if ((n == 0)); then
    fail "USB sticks" "none. Plug an 8 GB+ installer stick and the private keybag stick, then re-run."
    return 1
  fi
  i=0
  while ((i < n)); do
    id=${MACOS_USB_DISKS[$i]}
    fit=$(_macos_disk_installer_fit "$id")
    extra=
    case $fit in
      ok) extra='  ·  ≥8 GB, OK for installer' ;;
      tight) extra='  ·  fits ISO, prefer 8 GB+' ;;
      small) extra='  ·  TOO SMALL for installer ISO' ;;
    esac
    info "$id" "$(_macos_describe "$id" | sed "s/^$id  //")${extra}"
    i=$((i + 1))
  done
  if ((n == 1)); then
    fail "USB sticks" "only ${MACOS_USB_DISKS[0]}. Need two distinct disks: installer vs private."
    return 1
  fi
  if ((n == 2)); then
    ok "USB sticks" "${MACOS_USB_DISKS[0]} and ${MACOS_USB_DISKS[1]}"
  else
    info "USB sticks" "$n USB disks — map installer vs private; ignore extras"
  fi
  return 0
}

_macos_disk_in_usb() {
  local want=$1 id
  local i n
  n=${#MACOS_USB_DISKS[@]}
  i=0
  while ((i < n)); do
    id=${MACOS_USB_DISKS[$i]}
    [[ $id == "$want" ]] && return 0
    i=$((i + 1))
  done
  return 1
}

_macos_guess_pair() {
  # Sets MACOS_INSTALLER / MACOS_PRIVATE defaults when n==2 and roles are unique.
  local a b ra rb
  ((${#MACOS_USB_DISKS[@]} == 2)) || return 1
  a=${MACOS_USB_DISKS[0]}
  b=${MACOS_USB_DISKS[1]}
  ra=$(_macos_stick_role "$a")
  rb=$(_macos_stick_role "$b")
  [[ $(_macos_disk_installer_fit "$a") == small ]] && [[ $ra == installer ]] && ra=unknown
  [[ $(_macos_disk_installer_fit "$b") == small ]] && [[ $rb == installer ]] && rb=unknown
  if [[ $ra == installer && $rb != installer ]]; then
    MACOS_INSTALLER=$a
    MACOS_PRIVATE=$b
    return 0
  fi
  if [[ $rb == installer && $ra != installer ]]; then
    MACOS_INSTALLER=$b
    MACOS_PRIVATE=$a
    return 0
  fi
  if [[ $ra == private && $rb != private ]]; then
    MACOS_PRIVATE=$a
    MACOS_INSTALLER=$b
    return 0
  fi
  if [[ $rb == private && $ra != private ]]; then
    MACOS_PRIVATE=$b
    MACOS_INSTALLER=$a
    return 0
  fi
  return 1
}

_macos_confirm_id() {
  local want=$1 prompt=$2 got
  if ((ASSUME_YES)); then
    log "assuming $want (--yes)" "$prompt"
    return 0
  fi
  got=$(ask_line "$prompt" "")
  got=$(_macos_norm_disk "$got")
  [[ $got == "$want" ]] || die "typed $got, wanted $want" "roles are locked. Re-run and type the identifier exactly."
}

macos_map_sticks() {
  local a_inst a_priv
  _macos_need_darwin "macos"
  _macos_collect_usb
  if ! _macos_print_usb; then
    die "need two USB whole disks" "installer vs private. A keyboard does not count."
  fi

  if [[ -n $MACOS_INSTALLER ]]; then
    MACOS_INSTALLER=$(_macos_norm_disk "$MACOS_INSTALLER")
  fi
  if [[ -n $MACOS_PRIVATE ]]; then
    MACOS_PRIVATE=$(_macos_norm_disk "$MACOS_PRIVATE")
  fi

  if [[ -z $MACOS_INSTALLER || -z $MACOS_PRIVATE ]]; then
    if ((ASSUME_YES)); then
      die "--yes flashing needs explicit disks" \
        "pass --installer diskN --private diskM (two different USB whole disks)"
    fi
    if [[ -z $MACOS_INSTALLER && -z $MACOS_PRIVATE ]]; then
      _macos_guess_pair || true
    fi
    a_inst=$MACOS_INSTALLER
    a_priv=$MACOS_PRIVATE
    section "Pick roles" "Installer must be ≥8 GB. That disk will be ERASED — every file and partition."
    MACOS_INSTALLER=$(_macos_norm_disk "$(ask_line "Installer disk (≥8 GB; Omarchy ISO ERASES ALL DATA on it)" "$a_inst")")
    MACOS_PRIVATE=$(_macos_norm_disk "$(ask_line "Private disk (keybags — never the installer, not erased by dd)" "$a_priv")")
  fi

  [[ $MACOS_INSTALLER != "$MACOS_PRIVATE" ]] || \
    die "installer and private are both $MACOS_INSTALLER" "they must be two different USB disks"
  _macos_assert_usb "$MACOS_INSTALLER"
  _macos_assert_usb "$MACOS_PRIVATE"
  _macos_disk_in_usb "$MACOS_INSTALLER" || \
    die "$MACOS_INSTALLER is not a plugged USB disk" "unplug extras, plug both sticks, re-run"
  _macos_disk_in_usb "$MACOS_PRIVATE" || \
    die "$MACOS_PRIVATE is not a plugged USB disk" "unplug extras, plug both sticks, re-run"
  _macos_assert_installer_size "$MACOS_INSTALLER"

  section "Mapped"
  ok "installer  $MACOS_INSTALLER" "$(_macos_describe "$MACOS_INSTALLER" | sed "s/^$MACOS_INSTALLER  //")  ← ISO, ALL DATA ERASED"
  ok "private    $MACOS_PRIVATE" "$(_macos_describe "$MACOS_PRIVATE" | sed "s/^$MACOS_PRIVATE  //")  ← keybags, never gist"
  warn "Flashing $MACOS_INSTALLER erases ALL data on that stick" \
    "every partition, every file. $MACOS_PRIVATE and disk0 are not touched."
  if ! ((ASSUME_YES)); then
    if ! ask_yn "Erase ALL data on $MACOS_INSTALLER (the installer stick)?" n; then
      die "stopped — that stick would have been wiped" "re-run with a different --installer disk"
    fi
  fi
  hint "Never dd the ISO onto $MACOS_PRIVATE. Never copy keybags onto $MACOS_INSTALLER."
}

macos_sticks() {
  _macos_need_darwin "macos sticks"
  section "Internal" "Do not dd here. Shrink only the APFS container (usually disk0s2)."
  diskutil list internal physical
  _macos_collect_usb
  _macos_print_usb
}

_macos_iso_dest() {
  if [[ -n $MACOS_ISO ]]; then
    printf '%s\n' "$MACOS_ISO"
  else
    mkdir -p "$CACHE"
    printf '%s\n' "$CACHE/omarchy-${OMARCHY_ISO_VERSION}.iso"
  fi
}

macos_iso() {
  local dest got
  dest=$(_macos_iso_dest)
  expect "Omarchy ${OMARCHY_ISO_VERSION} ISO" \
    "Pinned SHA-256 ${OMARCHY_ISO_SHA256}" \
    "$OMARCHY_ISO_URL" \
    "~6.3 GB. Cached at $dest. Do not substitute a newer ISO unless you change the pin."

  if [[ -f $dest ]]; then
    log "checking SHA-256" "$dest  (minutes on a 6 GB file)"
    if ((DRY_RUN)); then
      log "dry-run: would verify $dest"
      MACOS_ISO_PATH=$dest
      return 0
    fi
    got=$(_macos_sha256 "$dest")
    if [[ $(printf '%s' "$got" | tr '[:upper:]' '[:lower:]') == "$(printf '%s' "$OMARCHY_ISO_SHA256" | tr '[:upper:]' '[:lower:]')" ]]; then
      ok "ISO" "$dest"
      MACOS_ISO_PATH=$dest
      return 0
    fi
    warn "checksum mismatch" "got $got — deleting and re-downloading"
    rm -f "$dest"
  fi

  [[ -z $MACOS_ISO ]] || die "ISO $dest failed SHA-256" "download Omarchy ${OMARCHY_ISO_VERSION} or omit --iso"

  if ((DRY_RUN)); then
    log "dry-run: curl $OMARCHY_ISO_URL" "$dest"
    MACOS_ISO_PATH=$dest
    return 0
  fi

  command -v curl >/dev/null || die "curl missing"
  mkdir -p "$(dirname "$dest")"
  expect "Download" "Several minutes on a decent link. Safe to re-run — curl resumes."
  curl -fL --retry 3 --retry-delay 2 -C - --progress-bar \
    -o "${dest}.partial" "$OMARCHY_ISO_URL"
  mv -f "${dest}.partial" "$dest"
  log "checking SHA-256" "$dest"
  got=$(_macos_sha256 "$dest")
  if [[ $(printf '%s' "$got" | tr '[:upper:]' '[:lower:]') != "$(printf '%s' "$OMARCHY_ISO_SHA256" | tr '[:upper:]' '[:lower:]')" ]]; then
    rm -f "$dest"
    die "ISO checksum mismatch after download" "got $got want $OMARCHY_ISO_SHA256"
  fi
  ok "ISO" "$dest"
  MACOS_ISO_PATH=$dest
}

_macos_first_mount() {
  local disk=$1 d mp
  mp=$(_macos_diskutil_val "$disk" "Mount Point")
  case $mp in
    /*) printf '%s\n' "$mp"; return 0 ;;
  esac
  while IFS= read -r d; do
    [[ -n $d ]] || continue
    mp=$(_macos_diskutil_val "$d" "Mount Point")
    case $mp in
      /*)
        printf '%s\n' "$mp"
        return 0
        ;;
    esac
  done < <(diskutil list "$disk" 2>/dev/null | awk '$NF ~ /^disk[0-9]+s[0-9]+$/ { print $NF }')
  return 1
}

_macos_private_mount() {
  local disk=$1 mp
  disk=$(_macos_norm_disk "$disk")
  [[ $disk == "$MACOS_INSTALLER" ]] && die "refusing to mount the installer as private" "$disk"
  if mp=$(_macos_first_mount "$disk"); then
    MACOS_PRIVATE_MOUNT=$mp
    return 0
  fi
  if ((DRY_RUN)); then
    log "dry-run: would mount or erase $disk as ExFAT KEYBAGS"
    MACOS_PRIVATE_MOUNT=/Volumes/KEYBAGS
    return 0
  fi
  if diskutil mountDisk "/dev/$disk" >/dev/null 2>&1; then
    if mp=$(_macos_first_mount "$disk"); then
      MACOS_PRIVATE_MOUNT=$mp
      return 0
    fi
  fi
  expect "Private stick has no writable volume" \
    "It will be erased as ExFAT named KEYBAGS. That destroys $disk only — not ${MACOS_INSTALLER:-the installer}, not disk0."
  _macos_confirm_id "$disk" "Type $disk to erase that private stick as ExFAT KEYBAGS"
  run as_root diskutil eraseDisk ExFAT KEYBAGS "/dev/$disk"
  mp=$(_macos_first_mount "$disk") || die "private stick did not mount after erase"
  MACOS_PRIVATE_MOUNT=$mp
}

_macos_refuse_installer_out() {
  local out=$1 mp
  [[ -n $MACOS_INSTALLER ]] || return 0
  mp=$(_macos_first_mount "$MACOS_INSTALLER" || true)
  [[ -n ${mp:-} ]] || return 0
  case $out in
    "$mp"|"$mp"/*)
      die "refusing to write onto the installer volume" "$out"
      ;;
  esac
}

macos_copy_pack() {
  local dest
  _macos_ensure_private_mount
  if [[ -z ${MACOS_PRIVATE_MOUNT:-} ]]; then
    if ((DRY_RUN)) && [[ -n ${MACOS_PRIVATE:-} ]]; then
      log "dry-run: would mount $MACOS_PRIVATE and pack toolbox onto KEYBAGS"
      return 0
    fi
    if [[ -n ${MACOS_PRIVATE:-} ]]; then
      warn "private stick $MACOS_PRIVATE has no mount — toolbox not copied" \
        "plug it, then: mbp16-1 macos export --private $MACOS_PRIVATE"
    else
      warn "toolbox not copied onto a private stick" \
        "pass --private diskN so KEYBAGS gets ${PACK_NAME}/ next to t2-touchid-export/"
    fi
    return 0
  fi
  dest="$MACOS_PRIVATE_MOUNT/$PACK_NAME"
  _macos_refuse_installer_out "$dest"
  expect "Copy toolbox onto the private stick" \
    "Shareable pack: README, bin, lib, files, kernel, macos, scripts, mbp16-1-powerd source." \
    "Not keybags. Not the private diary. The ISO flash does not touch this stick."
  _pack_helpers_identical
  if ((DRY_RUN)); then
    log "dry-run: pack --force $dest"
    return 0
  fi
  _pack_write "$dest" 1 1
  if [[ -d $ROOT/.git && ! -f $ROOT/CONTINUE.md ]]; then
    rm -rf "$dest/.git"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a "$ROOT/.git" "$dest/"
    else
      cp -a "$ROOT/.git" "$dest/"
    fi
  fi
  cat >"$MACOS_PRIVATE_MOUNT/START-HERE.txt" <<EOF
MacBookPro16,1 — Omarchy dual-boot (keep macOS)

Easy path (Linux — two commands):

  cd /run/media/\$USER/KEYBAGS/${PACK_NAME}
  chmod +x bin/mbp16-1
  ./bin/mbp16-1 setup
  # reboot unplugged onto linux-t2-mbp161 (do not suspend on stock)
  ./bin/mbp16-1 apply touchid

  ${PACK_NAME}/            toolbox + README (Easy path, then Detailed guide)
  t2-touchid-export/       keybags + catacomb — never gist, never the installer stick

If the lid is black: USB keyboard, Limine e, module_blacklist=amdgpu, F10, login,
then setup. Reboot WITHOUT that token, setup again.

Subcommands (one piece): mbp16-1 doctor, apply gpu / display / … — see README Detailed guide.
EOF
  ok "toolbox" "$dest"
  hint "after first Linux boot: cd to ${PACK_NAME} on this stick, then ./bin/mbp16-1 setup"
}

_macos_ensure_private_mount() {
  local mp
  [[ -n ${MACOS_PRIVATE_MOUNT:-} ]] && return 0
  [[ -n $MACOS_PRIVATE ]] || return 0
  if mp=$(_macos_first_mount "$MACOS_PRIVATE"); then
    MACOS_PRIVATE_MOUNT=$mp
    return 0
  fi
  if ((DRY_RUN)); then
    return 0
  fi
  if diskutil mountDisk "/dev/$MACOS_PRIVATE" >/dev/null 2>&1; then
    MACOS_PRIVATE_MOUNT=$(_macos_first_mount "$MACOS_PRIVATE" || true)
  fi
}

macos_flash() {
  local iso bytes stick_bytes
  [[ -n $MACOS_INSTALLER && -n $MACOS_PRIVATE ]] || \
    die "disks not mapped" "run: mbp16-1 macos   or pass --installer diskN --private diskM"
  iso=${1:-$(_macos_iso_dest)}
  [[ -f $iso ]] || die "ISO missing: $iso" "mbp16-1 macos  downloads it"
  bytes=$(_macos_file_bytes "$iso")
  stick_bytes=$(_macos_disk_bytes "$MACOS_INSTALLER")
  [[ -n $stick_bytes ]] || die "cannot read size of $MACOS_INSTALLER"
  if [[ -n $bytes && $stick_bytes -lt $bytes ]]; then
    die "$MACOS_INSTALLER is smaller than the ISO file" \
      "stick $(_macos_human_gb "$stick_bytes"), ISO $(_macos_human_gb "$bytes"). Use ≥8 GB."
  fi
  _macos_assert_installer_size "$MACOS_INSTALLER"

  expect "Flash installer $MACOS_INSTALLER — ERASES ALL DATA on that stick" \
    "Every partition and file on $MACOS_INSTALLER will be gone. $MACOS_PRIVATE is untouched. Not disk0." \
    "Need ≥8 GB (ISO ~6.3 GB). diskutil unmountDisk + dd to /dev/r${MACOS_INSTALLER} (bs=4m). Several minutes." \
    "macOS dd: press Ctrl-T for progress."
  _macos_confirm_id "$MACOS_INSTALLER" \
    "Type $MACOS_INSTALLER to ERASE ALL DATA on it and write the Omarchy ISO"

  if ((DRY_RUN)); then
    log "dry-run: diskutil unmountDisk /dev/$MACOS_INSTALLER"
    log "dry-run: dd if=$iso of=/dev/r${MACOS_INSTALLER} bs=4m"
    _macos_ensure_private_mount
    macos_copy_pack
    return 0
  fi
  run as_root diskutil unmountDisk "/dev/$MACOS_INSTALLER"
  run as_root dd "if=$iso" "of=/dev/r${MACOS_INSTALLER}" bs=4m
  sync
  ok "flashed" "$MACOS_INSTALLER  (orange EFI on Option-boot)"
  diskutil list "$MACOS_INSTALLER" || true
  _macos_ensure_private_mount
  macos_copy_pack
}

macos_export() {
  _macos_need_darwin "macos export"
  command -v git >/dev/null || die "git missing" "xcode-select --install, or brew install git"
  local out=${1:-} tools
  if [[ -z $out ]]; then
    if [[ -n $MACOS_PRIVATE ]]; then
      _macos_confirm_id "$MACOS_PRIVATE" \
        "Type $MACOS_PRIVATE to write keybags onto that stick (not the installer)"
      _macos_private_mount "$MACOS_PRIVATE"
      out="$MACOS_PRIVATE_MOUNT/t2-touchid-export"
    else
      out=$HOME/Desktop/t2-touchid-export
    fi
  fi
  _macos_refuse_installer_out "$out"
  expect "Clone t2-touchid-linux (if needed)" \
    "Usually under a minute. Uses jean-humann mbp161-mixed-envelope."
  ensure_touchid
  tools="$CACHE/t2-touchid-linux/tools/macos"
  [[ -x $tools/macos-export-keybags.sh ]] || die "missing $tools"
  expect "Export AppleKeyStore keybags" \
    "sudo find walks Preboot + Data looking for *.kb. Little output while it walks." \
    "Typical: 2–10 minutes (longer if /Users is huge). macOS will ask for your administrator password." \
    "Result is a small tar. Keep it on the private USB — never gist or commit it."
  if ((DRY_RUN)); then
    log "dry-run: $tools/macos-export-keybags.sh"
  else
    mkdir -p "$out"
    (cd "$tools" && ./macos-export-keybags.sh)
  fi
  expect "Export Touch ID catacomb" \
    "sudo find + tar of /Library/Catacomb (enrolled templates). Typical: 1–3 minutes." \
    "This run uses --no-reboot so you stay in macOS." \
    "The helper's default freezes biometrickitd and reboots immediately — we do not do that." \
    "Keep the archive on the private USB. Never gist it."
  if ((DRY_RUN)); then
    log "dry-run: $tools/macos-export-touchid-catacomb.sh --no-reboot"
    log "dry-run: copy tars to $out"
    macos_copy_pack
    return 0
  fi
  (cd "$tools" && ./macos-export-touchid-catacomb.sh --no-reboot)
  mkdir -p "$out"
  cp -a "$tools"/t2-keybags.tar.gz "$tools"/t2-touchid-catacomb.tar.gz "$out/"
  chmod 600 "$out"/t2-keybags.tar.gz "$out"/t2-touchid-catacomb.tar.gz 2>/dev/null || true
  macos_copy_pack
  section "Done"
  ok "archives" "$out"
  hint "private USB only, never gist, never the installer stick"
  hint "confirm Touch ID still works, then flash (if not already) and shut down ~30 s"
}

macos_map_apfs() {
  local stores=() id default= n
  if ((MACOS_CONTAINER_MAPPED)) && [[ -n $MACOS_CONTAINER ]]; then
    return 0
  fi
  _macos_need_darwin "macos shrink"
  section "Internal SSD" "Shrink the APFS physical store on this disk. Never a USB stick. Never disk0 as a whole disk."
  hint "Do not create a Linux partition. The Omarchy installer wants a hole on the map (free space AFTER the container)."
  diskutil list internal physical

  while IFS= read -r id; do
    [[ -n $id ]] || continue
    stores+=("$id")
  done < <(_macos_find_apfs_stores)

  n=${#stores[@]}
  if ((n == 0)); then
    die "no internal APFS physical store" "expected something like disk0s2 on this 16,1. Confirm diskutil list."
  fi
  section "APFS stores" "These are internal Apple_APFS slices. USB disks are excluded."
  for id in "${stores[@]}"; do
    info "$id" "$(_macos_diskutil_val "$id" "Disk Size")  $(_macos_diskutil_val "$id" "Device / Media Name")"
  done

  if [[ -n $MACOS_CONTAINER ]]; then
    MACOS_CONTAINER=$(_macos_norm_store "$MACOS_CONTAINER")
  fi
  default=${MACOS_CONTAINER:-}
  if [[ -z $default && $n -eq 1 ]]; then
    default=${stores[0]}
  fi

  if [[ -z $MACOS_CONTAINER ]]; then
    if ((ASSUME_YES)); then
      die "--yes shrinking needs --container diskNsM" "example: --container disk0s2  (not disk0, not a USB disk)"
    fi
    MACOS_CONTAINER=$(_macos_norm_store "$(ask_line "APFS container to shrink (internal store, usually disk0s2)" "$default")")
  fi

  _macos_diskutil_val "$MACOS_CONTAINER" Internal | grep -qx Yes || \
    die "$MACOS_CONTAINER is not internal" "refusing to shrink a USB or external disk"
  _macos_diskutil_val "$MACOS_CONTAINER" Protocol | grep -qi USB && \
    die "$MACOS_CONTAINER is USB" "that would be a stick, not the Mac SSD"

  local found=0
  for id in "${stores[@]}"; do
    [[ $id == "$MACOS_CONTAINER" ]] && found=1
  done
  ((found)) || die "$MACOS_CONTAINER is not an internal APFS store on this map" \
    "pick one of: ${stores[*]}"

  ok "container  $MACOS_CONTAINER" "$(_macos_diskutil_val "$MACOS_CONTAINER" "Disk Size")  on $(_macos_whole_from_store "$MACOS_CONTAINER")"
  MACOS_CONTAINER_MAPPED=1
}

macos_shrink() {
  local keep_arg=${1:-}
  local current rec_min file_min existing want min_free additional new_keep result_free whole
  [[ -n $keep_arg ]] && MACOS_KEEP=$keep_arg
  macos_map_apfs
  whole=$(_macos_whole_from_store "$MACOS_CONTAINER")

  expect "APFS shrink — unallocated space for Omarchy" \
    "Minimum hole: $(_macos_human_gb "$OMARCHY_FREE_MIN_BYTES") (floor). Request: $(_macos_human_gb "$OMARCHY_FREE_WANT_BYTES")." \
    "diskutil apfs resizeContainer relocates live APFS. Progress often sits still, then finishes." \
    "Typical on this 16,1 SSD: 20–40 minutes to free ~80 GB. Allow 1–2 hours if full or snapshots exist." \
    "Keep the Mac plugged in, lid open. Do not sleep, close the lid, or force-shutdown." \
    "Do not create a Linux partition — the installer wants free space AFTER $MACOS_CONTAINER."

  section "Resize limits for $MACOS_CONTAINER"
  diskutil apfs resizeContainer "$MACOS_CONTAINER" limits
  current=$(_macos_apfs_limit_bytes "$MACOS_CONTAINER" "Current Physical Store")
  rec_min=$(_macos_apfs_limit_bytes "$MACOS_CONTAINER" "Recommended minimum")
  file_min=$(_macos_apfs_limit_bytes "$MACOS_CONTAINER" "Minimum (constrained by file usage)")
  existing=$(_macos_existing_free_bytes "$whole")
  [[ -n $current ]] || die "could not parse resize limits for $MACOS_CONTAINER"
  rec_min=${rec_min:-$file_min}
  file_min=${file_min:-$rec_min}
  existing=${existing:-0}

  info "current container" "$(_macos_human_gb "$current")"
  info "macOS recommended min" "$(_macos_human_gb "${rec_min:-0}")"
  info "free on map now" "$(_macos_human_gb "$existing")  (after $MACOS_CONTAINER, not a new volume)"

  min_free=$OMARCHY_FREE_MIN_BYTES
  if [[ -n $MACOS_FREE && -n $MACOS_KEEP ]]; then
    die "pass --free or --keep, not both" "--free 80g is the Omarchy hole; --keep 360g is the new APFS size"
  fi
  if [[ -n $MACOS_FREE ]]; then
    want=$(_macos_parse_size_to_bytes "$MACOS_FREE")
  else
    want=$OMARCHY_FREE_WANT_BYTES
  fi
  if _macos_lt "$want" "$min_free"; then
    die "--free is below the $(_macos_human_gb "$min_free") floor" "Omarchy needs at least that hole"
  fi

  MACOS_SHRINK_SKIP=0
  if _macos_ge "$existing" "$want" || {
       _macos_ge "$want" 2000000000 && _macos_ge "$existing" "$(_macos_sub "$want" 1000000000)" && _macos_ge "$existing" "$min_free"
     }; then
    ok "unallocated" "$(_macos_human_gb "$existing") already on $whole  (request $(_macos_human_gb "$want"), floor $(_macos_human_gb "$min_free"))"
    hint "Do not create a Linux partition in that hole."
    MACOS_SHRINK_SKIP=1
    return 0
  fi

  if [[ -z $MACOS_KEEP && $MACOS_SHRINK_APPLY -eq 0 && -z $keep_arg && -z $MACOS_FREE ]]; then
    section "Next"
    additional=$(_macos_sub "$want" "$existing")
    new_keep=$(_macos_sub "$current" "$additional")
    hint "mbp16-1 macos                    shrinks $MACOS_CONTAINER to leave $(_macos_human_gb "$want")"
    hint "mbp16-1 macos shrink --keep $(_macos_human_gb "$new_keep")     or --free 80g"
    hint "20–40 min typical, up to 1–2 h — do not interrupt"
    return 0
  fi

  if [[ -n $MACOS_KEEP ]]; then
    new_keep=$(_macos_parse_size_to_bytes "$MACOS_KEEP")
    additional=$(_macos_sub "$current" "$new_keep")
    result_free=$(_macos_add "$existing" "$additional")
  else
    additional=$(_macos_sub "$want" "$existing")
    new_keep=$(_macos_sub "$current" "$additional")
    result_free=$want
    if [[ -n $rec_min ]] && _macos_lt "$new_keep" "$rec_min"; then
      new_keep=$rec_min
      additional=$(_macos_sub "$current" "$new_keep")
      result_free=$(_macos_add "$existing" "$additional")
      warn "can only shrink to macOS recommended minimum" \
        "that leaves $(_macos_human_gb "$result_free") free, not $(_macos_human_gb "$want")"
    fi
  fi

  if _macos_lt "$result_free" "$min_free"; then
    die "cannot free $(_macos_human_gb "$min_free") for Omarchy" \
      "limits allow $(_macos_human_gb "$result_free"). Delete local Time Machine snapshots and retry. Do not thin another Mac."
  fi
  if [[ -n $rec_min ]] && _macos_lt "$new_keep" "$rec_min"; then
    die "new container $(_macos_human_gb "$new_keep") is below macOS recommended minimum $(_macos_human_gb "$rec_min")" \
      "pick a larger --keep, or a smaller --free"
  fi

  section "Plan"
  ok "shrink $MACOS_CONTAINER" "from $(_macos_human_gb "$current") to $(_macos_human_gb "$new_keep")"
  ok "Omarchy hole" "$(_macos_human_gb "$result_free") unallocated after $MACOS_CONTAINER  (floor $(_macos_human_gb "$min_free"))"
  warn "Live APFS relocate" "20–40 min typical, up to 1–2 h. Plugged in, lid open, do not interrupt."
  _macos_confirm_store "$MACOS_CONTAINER" \
    "Type $MACOS_CONTAINER to shrink that APFS store (not a USB stick, not disk0 whole)"
  if ! ((ASSUME_YES)); then
    if ! ask_yn "Shrink $MACOS_CONTAINER to $(_macos_human_gb "$new_keep") and leave $(_macos_human_gb "$result_free") free for Omarchy?" n; then
      die "stopped — APFS was not resized"
    fi
  fi

  expect "Shrinking $MACOS_CONTAINER to $new_keep bytes" \
    "This is the long part. Little output is normal. Do not force-shutdown."
  if ((DRY_RUN)); then
    log "dry-run: diskutil apfs resizeContainer $MACOS_CONTAINER $new_keep"
    return 0
  fi
  run as_root diskutil apfs resizeContainer "$MACOS_CONTAINER" "$new_keep"
  section "Confirm free space" "Must appear AFTER $MACOS_CONTAINER, not as a new volume."
  diskutil list "$whole"
  existing=$(_macos_existing_free_bytes "$whole")
  if _macos_lt "${existing:-0}" "$min_free"; then
    die "free space after shrink is $(_macos_human_gb "${existing:-0}")" \
      "want ≥ $(_macos_human_gb "$min_free"). Check the map; do not create a Linux partition."
  fi
  ok "unallocated" "$(_macos_human_gb "$existing") on $whole"
}

macos_guide() {
  ui_meta "Easy path is macos, then setup, then apply touchid. This is the human checklist."
  section "Easy path" "README Easy path. One command on macOS, two on Linux."
  step 1 "mbp16-1 macos" "checks T2 / USB / Touch ID, asks a yes on each gate, then shrink → export → ISO → flash"
  step 2 "Option-boot orange EFI" "installer disk = Free space (keep macOS)"
  step 3 "mbp16-1 setup" "from KEYBAGS; then reboot onto linux-t2-mbp161"
  step 4 "mbp16-1 apply touchid" "then provision catacomb from t2-touchid-export/"

  section "Before macos" "Do not create a Linux partition. The installer wants a hole on the map."
  step 1 "Backup this Mac" "Time Machine or a clone. Dual-boot can go wrong. macos asks you to confirm."
  step 2 "Recovery (Command-R) → Startup Security Utility" "No Security + allow external media. macos checks; only Recovery can set it."
  step 3 "Enroll Touch ID" "macos checks bioutil when it can. Note: id -u  (often 501)."
  step 4 "Two USB sticks + wired keyboard" "installer ≥8 GB will be FULLY ERASED; private stick keeps keybags + toolbox"

  section "Subcommands" "Same path, one piece. See README Detailed guide."
  hint "macos sticks / shrink / export / flash    apply gpu / display / …    doctor"
  hint "Guide: README.md"
}

macos_banner() {
  local icon="$ROOT/macos/icon.txt" line art_cell txt
  local -a art=() texts=()
  local i w=0 n start

  texts=(
    "Omarchy dual-boot installer"
    "MacBookPro16,1  ·  keep macOS"
    "ISO ${OMARCHY_ISO_VERSION}"
  )

  if [[ -f $icon ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      art+=("$line")
      ((${#line} > w)) && w=${#line}
    done <"$icon"
  fi

  printf '\n'
  n=${#art[@]}
  if ((n == 0)); then
    printf '  %s%s%s\n' "$C_BOLD" "${texts[0]}" "$C_RESET"
    printf '  %s%s%s\n' "$C_DIM" "${texts[1]}" "$C_RESET"
    printf '  %s%s%s\n' "$C_DIM" "${texts[2]}" "$C_RESET"
    return 0
  fi

  start=$(( (n - 3) / 2 ))
  ((start < 0)) && start=0

  for ((i = 0; i < n; i++)); do
    printf '  '
    art_cell=$(printf '%-*s' "$w" "${art[i]}")
    if ((UI_COLOR)); then
      printf '%s%s%s' "$C_BOLD$C_CYAN" "$art_cell" "$C_RESET"
    else
      printf '%s' "$art_cell"
    fi
    if ((i >= start && i < start + 3)); then
      txt=${texts[$((i - start))]}
      printf '   '
      if ((i == start)); then
        printf '%s%s%s' "$C_BOLD" "$txt" "$C_RESET"
      else
        printf '%s%s%s' "$C_DIM" "$txt" "$C_RESET"
      fi
    fi
    printf '\n'
  done
}

macos_run() {
  _macos_need_darwin "macos"
  command -v git >/dev/null || die "git missing" "xcode-select --install, or brew install git"
  command -v curl >/dev/null || die "curl missing"
  ui_meta "Easy path on macOS: checks, then a yes on each gate, then shrink → export → ISO → flash."
  section "This command will" "Serial on the internal SSD. Do not overlap these jobs."
  hint "Map APFS + two USB disks, shrink if the hole is short (20–40 min), export keybags + toolbox, download ISO, erase the installer stick."
  _macos_easy_preflight
  macos_map_apfs
  macos_map_sticks
  MACOS_SHRINK_APPLY=1
  macos_shrink
  macos_export
  macos_iso
  macos_flash "${MACOS_ISO_PATH:-$(_macos_iso_dest)}"
  section "Next"
  hint "Confirm Touch ID still works on macOS."
  hint "Shut down ~30 s. Power on, hold Option, pick orange EFI Boot."
  hint "Installer disk = Free space (the APFS hole). Not entire disk. Not Apple's ~300 MB EFI."
  hint "Keep the private stick: toolbox in ${PACK_NAME}/, keybags in t2-touchid-export/ — never gist the tars."
}

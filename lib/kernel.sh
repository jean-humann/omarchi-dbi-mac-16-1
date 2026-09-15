# linux-t2-mbp161 lifecycle. Sourced from bin/mbp16-1.

KERNEL_UPSTREAM_DIR="$CACHE/linux-t2-arch"

kernel_daily_ver() { pacman_q_ver "$KERNEL_PKGBASE"; }
kernel_stock_ver() { pacman_q_ver "$KERNEL_STOCK"; }
kernel_packaging_ver() { pkgbuild_nv "$KERNEL_DIR/PKGBUILD" || true; }
kernel_repo_stock_ver() {
  pacman -Si "$KERNEL_STOCK" 2>/dev/null | awk '/^Version/{ print $3; exit }' || true
}

kernel_copy_packaging() {
  local dest
  dest=$(kernel_build_dest)
  if ((DRY_RUN)); then
    log "dry-run: copy kernel packaging → $dest"
    return 0
  fi
  mkdir -p "$dest"
  cp -a "$KERNEL_DIR/PKGBUILD" "$KERNEL_DIR/config.x86_64" "$KERNEL_DIR"/yuters-000*.patch "$dest/"
  log "kernel packaging copied to $dest" "build dir for makepkg"
}

kernel_limine_quiet() {
  install_user_file "$FILES/home/.local/bin/mbp16-1-limine-quiet" \
    "$HOME/.local/bin/mbp16-1-limine-quiet" 0755
  if ((DRY_RUN)); then
    log "would run mbp16-1-limine-quiet" "timeout: 1, quiet: yes — after limine-update"
    return 0
  fi
  run as_root "$HOME/.local/bin/mbp16-1-limine-quiet"
}

kernel_write_boot_order() {
  install_root_file "$FILES/etc/limine-entry-tool.d/zz-mbp16-1-boot-order.conf" \
    /etc/limine-entry-tool.d/zz-mbp16-1-boot-order.conf
}

kernel_makepkg_install() {
  local dest
  dest=$(kernel_build_dest)
  precheck_kernel_build
  expect "makepkg ${KERNEL_PKGBASE}" \
    "Typically 45–90 minutes on this 8-core 16,1 (download + compile) — same length on a rebase as on the first install." \
    "Stay plugged in. Fans will ramp. Do not suspend mid-build." \
    "yuters ${KERNEL_YUTERS_REF} 0001–0005 apply after t2linux. If a patch rejects, stop — refresh those five (not yuters main)." \
    "Then mkinitcpio + limine-update (1–3 min), then mbp16-1-limine-quiet (timeout: 1, quiet: yes)." \
    "Then reboot unplugged onto ${KERNEL_PKGBASE}."
  if ((DRY_RUN)); then
    log "dry-run: makepkg -si in $dest, zz-mbp16-1-boot-order.conf, limine-update, mbp16-1-limine-quiet"
    return 0
  fi
  local extra=()
  if [[ ${1:-} == --force ]]; then
    extra=(-C -f)
  fi
  if ! (cd "$dest" && makepkg -si "${extra[@]+"${extra[@]}"}"); then
    die "makepkg failed" \
      "If a yuters-000*.patch rejected, linux-t2 moved enough that ${KERNEL_YUTERS_REF} needs a refresh. Do not use yuters main / Falcon."
  fi
  kernel_write_boot_order
  rebuild_boot
  confirm_ready "Reboot onto ${KERNEL_PKGBASE}" \
    "Unplug USB-C. Pick ${KERNEL_PKGBASE} (Limine default after this install)." \
    "Do not suspend on stock ${KERNEL_STOCK}. Two lid-only s2idle, then one with USB-C if you use it."
}

# Fetch Watanare linux-t2-arch (read-only clone used to rebase packaging).
kernel_fetch_upstream() {
  local dir=$KERNEL_UPSTREAM_DIR
  mkdir -p "$(dirname "$dir")"
  if [[ -d $dir && ! -d $dir/.git ]]; then
    rm -rf "$dir"
  fi
  if [[ -d $dir/.git ]]; then
    git -C "$dir" fetch --quiet --depth 1 origin "$KERNEL_UPSTREAM_BRANCH"
    git -C "$dir" checkout --quiet -B "$KERNEL_UPSTREAM_BRANCH" "origin/${KERNEL_UPSTREAM_BRANCH}"
    log "updated  $dir"
  else
    git clone --quiet --branch "$KERNEL_UPSTREAM_BRANCH" --single-branch --depth 1 \
      "$KERNEL_UPSTREAM_REPO" "$dir"
    log "cloned  $dir"
  fi
}

kernel_upstream_nv() {
  pkgbuild_nv "$KERNEL_UPSTREAM_DIR/PKGBUILD"
}

kernel_upstream_commit() {
  git -C "$KERNEL_UPSTREAM_DIR" rev-parse --short HEAD 2>/dev/null || true
}

kernel_sync_run() {
  local out st=0 line
  set +e
  out=$(python3 "$ROOT/lib/kernel_sync.py" \
    --dest "$KERNEL_DIR" \
    --upstream "$KERNEL_UPSTREAM_DIR" \
    --commit "$(kernel_upstream_commit)" \
    "$@")
  st=$?
  set -e
  while IFS= read -r line; do
    [[ -n $line ]] && log "$line"
  done <<<"$out"
  return "$st"
}

kernel_sync_packaging() {
  local extra=()
  if ((DRY_RUN)); then
    extra+=(--dry-run)
  fi
  kernel_sync_run "${extra[@]+"${extra[@]}"}"
}

kernel_sync_check() {
  kernel_sync_run --dry-run
}

# Print version rows for doctor / update --check. Does not fetch.
kernel_report_versions() {
  local running daily stock repo pack kr=0 behind=0 syu=0
  running=$(kernel_running_pkgbase)
  daily=$(kernel_daily_ver)
  stock=$(kernel_stock_ver)
  repo=$(kernel_repo_stock_ver)
  pack=$(kernel_packaging_ver)

  if [[ $running == "$KERNEL_PKGBASE" && -n $daily && -n $stock ]]; then
    ok "Daily ${KERNEL_PKGBASE} ${daily}  ·  recovery ${stock}"
  else
    if [[ $running == "$KERNEL_PKGBASE" ]]; then
      ok "Daily ${KERNEL_PKGBASE}" "$(uname -r)"
    elif [[ $running == "$KERNEL_STOCK" ]]; then
      fail "Running stock ${KERNEL_STOCK}" "reboot onto ${KERNEL_PKGBASE} — do not suspend"
      kr=1
    else
      fail "Running ${running}" "boot ${KERNEL_PKGBASE}"
      kr=1
    fi
    if [[ -z $daily ]]; then
      fail "${KERNEL_PKGBASE} not installed" "mbp16-1 apply kernel --build"
      kr=1
    fi
    if [[ -z $stock ]]; then
      fail "${KERNEL_STOCK} not installed" "pacman -S ${KERNEL_STOCK} ${KERNEL_STOCK}-headers"
      ui_next "pacman -S ${KERNEL_STOCK} ${KERNEL_STOCK}-headers"
      kr=1
    fi
  fi

  if [[ -z $pack ]]; then
    fail "Toolbox PKGBUILD unreadable" "$KERNEL_DIR/PKGBUILD"
    kr=1
  elif [[ -n $daily && $pack != "$daily" ]]; then
    info "Toolbox PKGBUILD ${pack} ≠ installed ${daily}" "mbp16-1 update kernel"
    behind=1
  fi

  if [[ -n $daily && -n $stock ]] && kernel_ver_gt "$stock" "$daily"; then
    info "Behind stock ${stock}" "mbp16-1 update kernel"
    behind=1
  fi
  if [[ -n $pack && -n $stock ]] && kernel_ver_gt "$stock" "$pack"; then
    behind=1
  fi
  if [[ -n $repo && -n $stock ]] && kernel_ver_gt "$repo" "$stock"; then
    info "Repo ${KERNEL_STOCK} ${repo} > installed ${stock}" "omarchy update  (not pacman -Syu)"
    syu=1
    behind=1
  fi

  if ((syu)); then
    ui_next "omarchy update"
    ui_next "mbp16-1-limine-quiet"
  fi
  if ((behind)); then
    ui_next "mbp16-1 update kernel"
  elif [[ -z $daily ]]; then
    ui_next "mbp16-1 apply kernel --build"
  fi
  if [[ $running != "$KERNEL_PKGBASE" ]]; then
    ui_next "reboot unplugged onto ${KERNEL_PKGBASE}"
  fi
  return "$kr"
}

mbp16_1_update_kernel() {
  require_16_1
  is_linux || die "update kernel is Linux-only"
  local check=0 force=0 arg dest
  dest=$(kernel_build_dest)
  for arg in "$@"; do
    case $arg in
      --check) check=1 ;;
      --force) force=1 ;;
      --build) ;; # default; accepted so apply kernel --build muscle memory works
      *) die "unknown update kernel flag $arg" "use --check or --force" ;;
    esac
  done

  if ((check)); then
    expect "${KERNEL_PKGBASE} — report only" \
      "Fetches linux-t2-arch (${KERNEL_UPSTREAM_BRANCH}) into the cache. Does not write kernel/, does not compile." \
      "Stock ${KERNEL_STOCK} is recovery. Daily is ${KERNEL_PKGBASE} (same tree + yuters ${KERNEL_YUTERS_REF} 0001–0005)." \
      "If a rebuild is due, next is: mbp16-1 update kernel"
    section "Installed" "Local pacman + toolbox PKGBUILD (same rows as doctor Kernel)."
    kernel_report_versions || true
  else
    expect "${KERNEL_PKGBASE} lifecycle" \
      "Stock ${KERNEL_STOCK} is recovery. Daily is ${KERNEL_PKGBASE} (linux-t2-arch + yuters ${KERNEL_YUTERS_REF} 0001–0005)." \
      "Fetches upstream. Rebases and compiles only if daily or toolbox packaging is behind — or if you passed --force." \
      "Does not provide/replace linux. CONFIG_RUST stays off. Do not run yuters install.sh or main."
    ensure_core
    ensure_kernel_build_tools
  fi

  section "Upstream linux-t2-arch" "Read-only clone/fetch ${KERNEL_UPSTREAM_REPO} (${KERNEL_UPSTREAM_BRANCH})."
  if ((DRY_RUN)) && [[ ! -d $KERNEL_UPSTREAM_DIR/.git ]]; then
    log "dry-run: would clone linux-t2-arch into $KERNEL_UPSTREAM_DIR"
    if ((check)); then
      return 0
    fi
    log "dry-run: would sync PKGBUILD + config.x86_64, then makepkg -si in $dest"
    return 0
  fi
  kernel_fetch_upstream

  local pack up daily stock st=0 files_stale=0 need_build=0
  pack=$(kernel_packaging_ver)
  up=$(kernel_upstream_nv) || true
  daily=$(kernel_daily_ver)
  stock=$(kernel_stock_ver)
  ok "linux-t2-arch ${up:-unknown}" "commit $(kernel_upstream_commit)"
  [[ -n $pack ]] && ok "toolbox packaging ${pack}"
  [[ -n $daily ]] && ok "installed ${KERNEL_PKGBASE} ${daily}"
  [[ -n $stock ]] && ok "installed ${KERNEL_STOCK} ${stock}"

  if ((check)); then
    kernel_sync_check || st=$?
    if ((st != 0 && st != 2)); then
      die "kernel sync check failed" "see lib/kernel_sync.py"
    fi
    if ((st == 0)); then
      files_stale=1
    fi
    if ((force)) || [[ -z $daily ]]; then
      need_build=1
    elif [[ -n $up && -n $daily ]] && kernel_ver_gt "$up" "$daily"; then
      need_build=1
    elif ((files_stale)); then
      need_build=1
    fi
    if ((files_stale)); then
      info "packaging would rebase" "${pack}  ->  ${up}  (pkgver, T2_PATCH_HASH, checksums, config.x86_64)"
    else
      ok "packaging already matches linux-t2-arch" "$pack"
    fi
    if ((need_build)); then
      info "a rebuild is due"
      section "Next" "This --check did not compile."
      hint "mbp16-1 update kernel" "rebase + makepkg, typically 45–90 min, plugged in"
      hint "reboot unplugged onto ${KERNEL_PKGBASE}" "do not suspend on stock ${KERNEL_STOCK}"
    else
      ok "daily package is current relative to linux-t2-arch" "${daily:-missing}  vs  ${up}"
    fi
    return 0
  fi

  if ((force)) || [[ -z $daily ]]; then
    need_build=1
  elif [[ -n $up && -n $daily ]] && kernel_ver_gt "$up" "$daily"; then
    need_build=1
  elif [[ -n $up && -n $pack && $up != "$pack" ]]; then
    need_build=1
  fi

  if ((need_build == 0)); then
    ok "already current" "${KERNEL_PKGBASE} ${daily} matches linux-t2-arch ${up}"
    hint "rebuild anyway: mbp16-1 update kernel --force"
    return 0
  fi

  expect "Rebuild ${KERNEL_PKGBASE}  ${pack:-?}  →  ${up}" \
    "1. Rebase toolbox kernel/ — pkgver, T2_PATCH_HASH, checksums, config.x86_64. Keep yuters 0001–0005, pkgbase, CONFIG_RUST off." \
    "2. Copy that packaging to the build dir: $dest" \
    "3. makepkg -si — typically 45–90 min. If a yuters patch rejects, stop (not yuters main)." \
    "4. mkinitcpio + limine-update (1–3 min), then mbp16-1-limine-quiet." \
    "5. Reboot unplugged onto ${KERNEL_PKGBASE}. Two lid-only s2idle, then one with USB-C if you use it."

  section "Rebase packaging" "Writes $KERNEL_DIR. Does not touch yuters-000*.patch files."
  st=0
  kernel_sync_packaging || st=$?
  if ((st == 2)); then
    info "sync made no file changes" "versions already matched on disk"
  elif ((st != 0)); then
    die "kernel sync failed" "see lib/kernel_sync.py"
  else
    ok "packaging rebased onto linux-t2-arch ${up}"
  fi

  kernel_copy_packaging
  if ((force)); then
    kernel_makepkg_install --force
  else
    kernel_makepkg_install
  fi
}

mbp16_1_update() {
  local what=${1:-kernel}
  shift || true
  case $what in
    kernel) mbp16_1_update_kernel "$@" ;;
    *) die "unknown update target $what" "try: mbp16-1 update kernel" ;;
  esac
}

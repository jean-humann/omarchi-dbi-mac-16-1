# Runtime / build dependencies. Sourced from bin/mbp16-1.
# Arch packages: omarchy-pkg-add (pacman --needed).
# Rust: omarchy install dev-env rust (rustup), not the Arch rust package.

DEPS_CORE_DONE=0
DEPS_KERNEL_DONE=0
DEPS_RUST_DONE=0
DEPS_TOUCHID_DONE=0

# python3, git, lspci, jq, socat — every Linux apply path.
# socat is required by mbp16-1-hypr-outputs --watch (Hyprland socket).
DEPS_CORE_PKGS=(python git pciutils jq socat)

# Kernel PKGBUILD makedepends that are not always in a fresh Omarchy install.
# gcc/make/fakeroot/patch come from the base-devel group.
DEPS_KERNEL_PKGS=(bc cpio pahole xxhash libelf openssl perl python tar xz zlib zstd git gettext)

# Touch ID install.sh: python venv + C module against this boot's headers + fprintd.
DEPS_TOUCHID_PKGS=(python fprintd)

have_pkg() {
  pacman -Q "$1" >/dev/null 2>&1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Prefer rustup (~/.cargo/env) when the login PATH is not in this script.
source_cargo_env() {
  have_cmd cargo && have_cmd rustc && return 0
  if [[ -f ${HOME}/.cargo/env ]]; then
    # shellcheck disable=SC1091
    source "${HOME}/.cargo/env"
  fi
  have_cmd cargo && have_cmd rustc
}

pkg_add() {
  local missing=() p
  ((${#@})) || return 0
  for p in "$@"; do
    have_pkg "$p" || missing+=("$p")
  done
  ((${#missing[@]})) || return 0
  if ((DRY_RUN)); then
    log "dry-run: omarchy-pkg-add ${missing[*]}"
    return 0
  fi
  expect "Install packages" \
    "Omarchy: omarchy-pkg-add (pacman -S --noconfirm --needed). Not a raw curl installer."
  if have_cmd omarchy-pkg-add; then
    omarchy-pkg-add "${missing[@]}"
  else
    warn "omarchy-pkg-add not on PATH" "falling back to pacman -S --needed"
    run as_root pacman -S --noconfirm --needed "${missing[@]}"
  fi
  hash -r 2>/dev/null || true
  for p in "${missing[@]}"; do
    have_pkg "$p" || die "package $p did not install" "retry: omarchy-pkg-add $p"
  done
  log "installed  ${missing[*]}"
}

pkg_add_group() {
  local group=$1
  local pkgs=()
  mapfile -t pkgs < <(pacman -Sqg "$group" 2>/dev/null)
  ((${#pkgs[@]})) || die "package group ${group} not found" "sync pacman databases and retry"
  pkg_add "${pkgs[@]}"
}

ensure_cmd() {
  local cmd=$1
  shift
  have_cmd "$cmd" && return 0
  pkg_add "$@"
  hash -r 2>/dev/null || true
  have_cmd "$cmd" || die "$cmd still missing" "fix: omarchy-pkg-add $*"
}

ensure_core() {
  is_linux || return 0
  ((DEPS_CORE_DONE)) && return 0
  pkg_add "${DEPS_CORE_PKGS[@]}"
  ensure_cmd python3 python
  ensure_cmd git git
  ensure_cmd jq jq
  ensure_cmd lspci pciutils
  ensure_cmd socat socat
  DEPS_CORE_DONE=1
}

ensure_kernel_build_tools() {
  is_linux || return 0
  ((DEPS_KERNEL_DONE)) && return 0
  ensure_core
  pkg_add_group base-devel
  pkg_add "${DEPS_KERNEL_PKGS[@]}"
  ensure_cmd makepkg pacman
  ensure_cmd pahole pahole
  ensure_cmd bc bc
  DEPS_KERNEL_DONE=1
}

ensure_rust() {
  is_linux || return 0
  ((DEPS_RUST_DONE)) && return 0
  if source_cargo_env; then
    DEPS_RUST_DONE=1
    return 0
  fi
  if ((DRY_RUN)); then
    log "dry-run: omarchy install dev-env rust" "rustup -y; not the Arch rust package"
    return 0
  fi
  expect "Install Rust" \
    "Omarchy: omarchy install dev-env rust (rustup). Needed to compile mbp16-1-powerd." \
    "Do not mix that with a later pacman rust unless you know you want the distro toolchain."
  if have_cmd omarchy-install-dev-env; then
    omarchy-install-dev-env rust
  else
    die "cargo/rustc missing" "fix: omarchy install dev-env rust"
  fi
  source_cargo_env || die "cargo still missing after rustup" \
    "open a new shell, or: source ~/.cargo/env    then retry"
  DEPS_RUST_DONE=1
}

ensure_touchid_packages() {
  is_linux || return 0
  ensure_core
  pkg_add_group base-devel
  pkg_add "${DEPS_TOUCHID_PKGS[@]}"
  ensure_cmd python3 python
  ensure_cmd make make
  ensure_cmd gcc gcc
}

ensure_touchid_build_tools() {
  is_linux || return 0
  ((DEPS_TOUCHID_DONE)) && return 0
  ensure_touchid_packages
  local builddir="/usr/lib/modules/$(uname -r)/build"
  if [[ ! -d $builddir ]]; then
    die "kernel headers missing for $(uname -r)" \
      "Touch ID compiles t2_sep_transport against this boot. Build/boot ${KERNEL_PKGBASE} first (headers package is ${KERNEL_PKGBASE}-headers)."
  fi
  DEPS_TOUCHID_DONE=1
}

_deps_cmd_row() {
  local cmd=$1 pkg=$2
  if have_cmd "$cmd"; then
    return 0
  fi
  fail "Missing ${cmd}" "mbp16-1 deps  (omarchy-pkg-add ${pkg})"
  ui_next "mbp16-1 deps"
  return 1
}

# Doctor / deps --check. One line when healthy; only missing tools get their own row.
deps_report() {
  local kr=0 c miss_core=() miss_build=()
  section "Tools" "omarchy-pkg-add  ·  omarchy install dev-env rust"

  if ! is_linux; then
    info "Linux-only"
    return 0
  fi

  source_cargo_env || true

  for c in python3 git jq lspci socat mkinitcpio limine-update; do
    have_cmd "$c" || miss_core+=("$c")
  done
  have_cmd cargo && have_cmd rustc || miss_build+=(cargo)
  have_cmd makepkg || miss_build+=(makepkg)
  have_cmd pahole || miss_build+=(pahole)

  if ((${#miss_core[@]} == 0 && ${#miss_build[@]} == 0)); then
    ok "python3 git jq lspci socat  ·  cargo makepkg pahole  ·  mkinitcpio limine-update"
  else
    if ((${#miss_core[@]})); then
      fail "Missing ${miss_core[*]}" "mbp16-1 setup"
      ui_next "mbp16-1 setup"
      kr=1
    else
      ok "python3 git jq lspci socat  ·  mkinitcpio limine-update"
    fi
    if ((${#miss_build[@]})); then
      info "Build tools missing: ${miss_build[*]}" "mbp16-1 setup"
      ui_next "mbp16-1 setup"
    fi
  fi

  if ! have_cmd omarchy-pkg-add; then
    info "omarchy-pkg-add missing" "deps falls back to pacman -S --needed"
  fi

  return "$kr"
}

mbp16_1_deps() {
  is_linux || die "deps is Linux-only"
  require_16_1
  local check=0 target=all arg
  for arg in "$@"; do
    case $arg in
      --check) check=1 ;;
      all|core|kernel|rust|touchid) target=$arg ;;
      *) die "unknown deps argument $arg" "use all|core|kernel|rust|touchid or --check" ;;
    esac
  done

  if ((check)); then
    deps_report || true
    return 0
  fi

  expect "Install toolbox runtimes" \
    "Arch packages: omarchy-pkg-add. Rust: omarchy install dev-env rust (rustup)." \
    "Does not install TLP / auto-cpufreq / watt / broadcom-wl / supergfxctl."

  case $target in
    all)
      ensure_core
      ensure_kernel_build_tools
      ensure_rust
      pkg_add "${DEPS_TOUCHID_PKGS[@]}"
      ;;
    core) ensure_core ;;
    kernel) ensure_kernel_build_tools ;;
    rust) ensure_rust ;;
    touchid) ensure_touchid_packages ;;
  esac

  section "Tools after install"
  deps_report || true
}

# Shared helpers for bin/mbp16-1. Sourced, not executed.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
FILES="$ROOT/files"
KERNEL_DIR="$ROOT/kernel"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/mbp16-1"
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mbp16-1/backups"

# Pinned installer ISO (proven on this 16,1). Override with MBP16_1_OMARCHY_ISO_*.
OMARCHY_ISO_VERSION="${MBP16_1_OMARCHY_ISO_VERSION:-4.0.3}"
OMARCHY_ISO_URL="${MBP16_1_OMARCHY_ISO_URL:-https://iso.omarchy.org/omarchy-${OMARCHY_ISO_VERSION}.iso}"
OMARCHY_ISO_SHA256="${MBP16_1_OMARCHY_ISO_SHA256:-03d60bc74306dca51f96e1a84b690871d8d606826b260edd0208962da8507d14}"
# 4.0.3 content-length. Stick must be at least this; ask for 8 GB advertised.
OMARCHY_ISO_BYTES="${MBP16_1_OMARCHY_ISO_BYTES:-6260654080}"
OMARCHY_FREE_MIN_BYTES="${MBP16_1_OMARCHY_FREE_MIN_BYTES:-32000000000}"
OMARCHY_FREE_WANT_BYTES="${MBP16_1_OMARCHY_FREE_WANT_BYTES:-80000000000}"
PACK_NAME="${MBP16_1_PACK_NAME:-omarchi-dbi-mac-16-1}"

RANDY_REPO="${MBP16_1_RANDY_REPO:-https://github.com/novuon/mbp2019-omarchy.git}"
TOUCHID_REPO="${MBP16_1_TOUCHID_REPO:-https://github.com/jean-humann/t2-touchid-linux.git}"
TOUCHID_BRANCH="${MBP16_1_TOUCHID_BRANCH:-mbp161-mixed-envelope}"

DRY_RUN=0
FORCE_MODEL=0
ASSUME_YES=0
LAYOUT=ask
EXTERNAL=ask
EXTERNAL_DESC=
EXTERNAL_MODE=preferred
EXTERNAL_SCALE=auto
EXTERNAL_POS=auto-center-up

EXPECTED_MODEL=MacBookPro16,1
INTEL_PCI=0000:00:02.0
AMD_PCI=0000:03:00.0
AMD_DEVICE=0x7340
KERNEL_PKGBASE=linux-t2-mbp161
KERNEL_STOCK=linux-t2
KERNEL_UPSTREAM_REPO="${MBP16_1_T2_ARCH_REPO:-https://github.com/NoaHimesaka1873/linux-t2-arch.git}"
KERNEL_UPSTREAM_BRANCH="${MBP16_1_T2_ARCH_BRANCH:-main}"
KERNEL_YUTERS_REF=e77b03f

UI_OK=0
UI_FAIL=0
UI_NOTE=0
UI_NEXT=()
UI_COLOR=0
C_RESET= C_BOLD= C_DIM= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_CYAN=
SYM_OK= SYM_FAIL= SYM_NOTE= SYM_WARN= SYM_ARROW=

ui_setup() {
  if [[ -n ${NO_COLOR:-} ]]; then
    UI_COLOR=0
  elif [[ -n ${CLICOLOR_FORCE:-} || -n ${FORCE_COLOR:-} ]]; then
    UI_COLOR=1
  elif [[ ${TERM:-} == dumb ]]; then
    UI_COLOR=0
  elif [[ -t 1 ]]; then
    UI_COLOR=1
  else
    UI_COLOR=0
  fi
  if ((UI_COLOR)); then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    SYM_OK='✓'
    SYM_FAIL='✗'
    SYM_NOTE='•'
    SYM_WARN='!'
    SYM_ARROW='→'
  else
    C_RESET= C_BOLD= C_DIM= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_CYAN=
    SYM_OK='ok'
    SYM_FAIL='FAIL'
    SYM_NOTE='--'
    SYM_WARN='WARN'
    SYM_ARROW='->'
  fi
}
ui_setup

ui_reset_counts() {
  UI_OK=0
  UI_FAIL=0
  UI_NOTE=0
  UI_NEXT=()
}

ui_command() {
  local name=$1
  printf '\n'
  printf '%s%s%s %s%s%s' "$C_BOLD$C_CYAN" "mbp16-1" "$C_RESET" "$C_BOLD" "$name" "$C_RESET"
  if ((DRY_RUN)); then
    printf '  %s%s%s' "$C_YELLOW" "dry-run" "$C_RESET"
  fi
  printf '\n'
}

ui_meta() {
  printf '  %s%s%s\n' "$C_DIM" "$*" "$C_RESET"
}

ui_end() {
  printf '\n'
}

# Category: title + one dim sentence. Always pass the sentence.
section() {
  local title=$1 hint=${2:-}
  printf '\n%s── %s%s\n' "$C_BOLD$C_CYAN" "$title" "$C_RESET"
  if [[ -n $hint ]]; then
    printf '  %s%s%s\n' "$C_DIM" "$hint" "$C_RESET"
  fi
}

_ui_row() {
  local color=$1 sym=$2 title=$3 detail=${4:-}
  if ((UI_COLOR)); then
    printf '  %s%s%s  %s\n' "$color" "$sym" "$C_RESET" "$title"
  else
    printf '  %-4s  %s\n' "$sym" "$title"
  fi
  if [[ -n $detail ]]; then
    printf '      %s%s%s\n' "$C_DIM" "$detail" "$C_RESET"
  fi
}

ok() {
  UI_OK=$((UI_OK + 1))
  _ui_row "${C_GREEN}" "$SYM_OK" "$1" "${2:-}"
}

fail() {
  UI_FAIL=$((UI_FAIL + 1))
  _ui_row "${C_RED}${C_BOLD}" "$SYM_FAIL" "$1" "${2:-}"
}

info() {
  UI_NOTE=$((UI_NOTE + 1))
  _ui_row "${C_YELLOW}" "$SYM_NOTE" "$1" "${2:-}"
}

hint() {
  _ui_row "${C_DIM}" "$SYM_ARROW" "$1" "${2:-}"
}

# Dim label inside a section (Hardware / Policy / Fans). No extra blank line.
subsection() {
  printf '  %s%s%s\n' "$C_DIM" "$1" "$C_RESET"
}

ui_next() {
  UI_NEXT+=("$1")
}

ui_print_next() {
  ((${#UI_NEXT[@]})) || return 0
  section "Next" "Run in order. Doctor does not change the machine."
  local i=1 line
  local -A _ui_next_seen=()
  for line in "${UI_NEXT[@]}"; do
    [[ -n ${_ui_next_seen[$line]+x} ]] && continue
    _ui_next_seen[$line]=1
    step "$i" "$line"
    i=$((i + 1))
  done
}

ui_kv() {
  local key=$1 val=$2
  printf '  %s%-32s%s%s\n' "$C_BOLD" "$key" "$C_RESET" "$val"
}

step() {
  local n=$1 title=$2 detail=${3:-}
  printf '  %s%s.%s  %s\n' "$C_BOLD$C_CYAN" "$n" "$C_RESET" "$title"
  if [[ -n $detail ]]; then
    printf '      %s%s%s\n' "$C_DIM" "$detail" "$C_RESET"
  fi
}

ui_summary() {
  ui_print_next
  section "Summary"
  if ((UI_FAIL == 0)); then
    printf '  %s%s%s  %d passed' "$C_GREEN" "$SYM_OK" "$C_RESET" "$UI_OK"
  else
    printf '  %s%s%s  %d failed' "$C_RED$C_BOLD" "$SYM_FAIL" "$C_RESET" "$UI_FAIL"
    printf '  %s·%s  %d passed' "$C_DIM" "$C_RESET" "$UI_OK"
  fi
  if ((UI_NOTE == 1)); then
    printf '  %s·%s  1 note' "$C_DIM" "$C_RESET"
  elif ((UI_NOTE)); then
    printf '  %s·%s  %d notes' "$C_DIM" "$C_RESET" "$UI_NOTE"
  fi
  printf '\n'
}

log() {
  _ui_row "${C_BLUE}" "$SYM_ARROW" "$1" "${2:-}"
}

warn() {
  _ui_row "${C_YELLOW}${C_BOLD}" "$SYM_WARN" "$1" "${2:-}" >&2
}

die() {
  _ui_row "${C_RED}${C_BOLD}" "$SYM_FAIL" "$1" "${2:-}" >&2
  ui_end
  exit 1
}

# Long-step banner. First argument is the title; the rest are explanation lines.
expect() {
  local title=$1
  shift
  section "$title"
  local line
  for line in "$@"; do
    printf '  %s%s%s\n' "$C_DIM" "$line" "$C_RESET"
  done
}

is_linux() { [[ $(uname -s) == Linux ]]; }
is_darwin() { [[ $(uname -s) == Darwin ]]; }

as_root() {
  if [[ $(id -u) -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

run() {
  if ((DRY_RUN)); then
    local cmd
    cmd=$(printf '%q ' "$@")
    _ui_row "${C_YELLOW}" "$SYM_ARROW" "dry-run  ${cmd% }" >&2
    return 0
  fi
  "$@"
}

product_name() {
  if is_linux && [[ -r /sys/class/dmi/id/product_name ]]; then
    tr -d '\n' </sys/class/dmi/id/product_name
  elif is_darwin; then
    sysctl -n hw.model
  else
    printf 'unknown'
  fi
}

require_16_1() {
  local model
  model=$(product_name)
  if [[ $model == "$EXPECTED_MODEL" ]]; then
    return 0
  fi
  if ((FORCE_MODEL)); then
    warn "model is ${model}" "continuing because --i-know"
    return 0
  fi
  die "this toolbox is for ${EXPECTED_MODEL} (got ${model})" \
    "Pass --i-know only if you measured the same PCI layout."
}

backup_if_exists() {
  local dest=$1
  [[ -e $dest ]] || return 0
  mkdir -p "$BACKUP_DIR"
  local stamp
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  local bak="$BACKUP_DIR/$(echo "$dest" | tr / _ | sed 's/^_//').$stamp"
  if ((DRY_RUN)); then
    log "would backup $dest" "$bak"
    return 0
  fi
  if [[ -w $(dirname "$dest") ]] && [[ $(id -u) -eq 0 || -w $dest ]]; then
    cp -a "$dest" "$bak"
  else
    as_root cp -a "$dest" "$bak"
  fi
  log "backed up $dest" "$bak"
}

install_root_file() {
  local src=$1 dest=$2 mode=${3:-0644}
  [[ -f $src ]] || die "missing template $src"
  if [[ -f $dest ]] && cmp -s "$src" "$dest"; then
    log "unchanged  $dest"
    return 0
  fi
  backup_if_exists "$dest"
  run as_root install -D -m "$mode" -o root -g root "$src" "$dest"
  if ((DRY_RUN)); then
    log "would install  $dest"
  else
    log "installed  $dest"
  fi
}

install_user_file() {
  local src=$1 dest=$2 mode=${3:-0644}
  [[ -f $src ]] || die "missing template $src"
  mkdir -p "$(dirname "$dest")"
  if [[ -f $dest ]] && cmp -s "$src" "$dest"; then
    log "unchanged  $dest"
    return 0
  fi
  backup_if_exists "$dest"
  if ((DRY_RUN)); then
    log "would install  $dest"
    return 0
  fi
  install -D -m "$mode" "$src" "$dest"
  log "installed  $dest"
}

file_has() {
  local path=$1 needle=$2
  [[ -f $path ]] && grep -Fq "$needle" "$path"
}

ensure_line() {
  local dest=$1 line=$2
  mkdir -p "$(dirname "$dest")"
  if [[ -f $dest ]] && grep -Fxq "$line" "$dest"; then
    log "already has line in $dest"
    return 0
  fi
  backup_if_exists "$dest"
  if ((DRY_RUN)); then
    log "would append to $dest"
    return 0
  fi
  touch "$dest"
  printf '%s\n' "$line" >>"$dest"
  log "appended to $dest"
}

prepend_if_missing() {
  local dest=$1 snippet=$2 needle=$3
  mkdir -p "$(dirname "$dest")"
  if [[ -f $dest ]] && grep -Fq "$needle" "$dest"; then
    log "already has ${needle} in $dest"
    return 0
  fi
  backup_if_exists "$dest"
  if ((DRY_RUN)); then
    log "would prepend $dest"
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  cat "$snippet" >"$tmp"
  printf '\n' >>"$tmp"
  if [[ -f $dest ]]; then
    cat "$dest" >>"$tmp"
  fi
  install -m 0644 "$tmp" "$dest"
  rm -f "$tmp"
  log "updated  $dest"
}

clone_or_update() {
  local url=$1 dir=$2 branch=${3:-}
  if ! command -v git >/dev/null 2>&1; then
    ensure_core
  fi
  mkdir -p "$(dirname "$dir")"
  if [[ -d $dir/.git ]]; then
    if ((DRY_RUN)); then
      log "would git fetch  $dir"
      return 0
    fi
    git -C "$dir" fetch --quiet --tags
    if [[ -n $branch ]]; then
      git -C "$dir" checkout --quiet "$branch"
    fi
    git -C "$dir" pull --ff-only --quiet || true
    log "updated  $dir"
    return 0
  fi
  if ((DRY_RUN)); then
    log "would git clone  $url" "$dir"
    return 0
  fi
  if [[ -n $branch ]]; then
    git clone --branch "$branch" --single-branch "$url" "$dir"
  else
    git clone "$url" "$dir"
  fi
  log "cloned  $dir"
}

ensure_randy() {
  clone_or_update "$RANDY_REPO" "$CACHE/mbp2019-omarchy"
}

ensure_touchid() {
  clone_or_update "$TOUCHID_REPO" "$CACHE/t2-touchid-linux" "$TOUCHID_BRANCH"
}

read_sys() {
  local path=$1
  [[ -r $path ]] && tr -d '\n' <"$path" || true
}

module_loaded() {
  awk -v m="$1" '$1 == m { found = 1 } END { exit !found }' /proc/modules 2>/dev/null
}

pacman_q_ver() {
  pacman -Q "$1" 2>/dev/null | awk '{ print $2; exit }' || true
}

# pkgbase of the running kernel (linux-t2-mbp161, linux-t2, …). Not a version string.
kernel_running_pkgbase() {
  local r
  r=$(uname -r)
  if [[ -r /usr/lib/modules/$r/pkgbase ]]; then
    tr -d '\n' </usr/lib/modules/"$r"/pkgbase
    return 0
  fi
  case $r in
    *-t2-mbp161) printf '%s\n' linux-t2-mbp161 ;;
    *-t2) printf '%s\n' linux-t2 ;;
    *) printf '%s\n' unknown ;;
  esac
}

pkgbuild_field() {
  local f=$1 key=$2
  [[ -f $f ]] || return 1
  awk -F= -v k="$key" '$1 == k { print $2; exit }' "$f"
}

pkgbuild_nv() {
  local f=$1 ver rel
  ver=$(pkgbuild_field "$f" pkgver) || return 1
  rel=$(pkgbuild_field "$f" pkgrel) || return 1
  [[ -n $ver && -n $rel ]] || return 1
  printf '%s-%s\n' "$ver" "$rel"
}

kernel_is_daily() {
  [[ $(kernel_running_pkgbase) == "$KERNEL_PKGBASE" ]]
}

kernel_build_dest() {
  printf '%s\n' "${MBP16_1_KERNEL_SRC:-$HOME/src/linux-t2-mbp161}"
}

# True if $1 is a newer pacman version than $2 (needs vercmp).
kernel_ver_gt() {
  [[ -n ${1:-} && -n ${2:-} ]] || return 1
  command -v vercmp >/dev/null 2>&1 || return 1
  [[ $(vercmp "$1" "$2") -gt 0 ]]
}

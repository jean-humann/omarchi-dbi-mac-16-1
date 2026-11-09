#!/bin/bash
# CI only. Builds linux-t2-mbp161 from kernel/ inside archlinux:latest, as root.
# Usage: build-kernel.sh REPO_DIR BUILD_DIR OUT_DIR
#
# Every source checksum and PGP signature is checked (never --skippgpcheck).
# OUT_DIR gets the two packages, SHA256SUMS, INPUTS, BUILDINFO.txt and VERSION.
# pb_eval takes PKGBUILD expressions in single quotes on purpose.
# shellcheck disable=SC2016
set -euo pipefail

repo=$1 build=$2 out=$3
pkgbuild=$repo/kernel/PKGBUILD

# Same pipeline as kernel_inputs_digest in lib/kernel.sh: the toolbox refuses
# the packages once kernel/ no longer hashes to this.
inputs=$(cd "$repo/kernel" &&
  find . -maxdepth 1 -type f ! -name README ! -name '*.md' ! -name 'prebuilt*' ! -name '.*' -print0 |
  LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | awk '{ print $1 }')

pb_eval() { bash -c 'source "$1" >/dev/null; eval "$2"' _ "$pkgbuild" "$1"; }

echo "::group::pacman"
# pacman's download sandbox needs Landlock, which the container may not allow.
grep -q '^DisableSandbox' /etc/pacman.conf ||
  sed -i '0,/^\[options\]/s//[options]\nDisableSandbox/' /etc/pacman.conf
pacman -Syu --noconfirm --needed base-devel git gnupg
mapfile -t deps < <(pb_eval 'printf "%s\n" "${makedepends[@]}"')
pacman -S --noconfirm --needed "${deps[@]}"
echo "::endgroup::"

id builder >/dev/null 2>&1 || useradd -m builder
mkdir -p "$build" "$out"
cp -a "$repo/kernel/." "$build/"
chown -R builder "$build"
as_builder() { su builder -s /bin/bash -c "$1"; }

echo "::group::PGP keys"
mapfile -t fprs < <(pb_eval 'printf "%s\n" "${validpgpkeys[@]}"')
if ! as_builder 'gpg --batch --auto-key-locate clear,wkd --locate-keys torvalds@kernel.org gregkh@kernel.org heftig@archlinux.org'; then
  as_builder "gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys ${fprs[*]}"
fi
for f in "${fprs[@]}"; do
  as_builder "gpg --batch --list-keys $f" >/dev/null ||
    { echo "missing PGP key $f" >&2; exit 1; }
done
echo "::endgroup::"

df -h "$build"
start=$(date +%s)
as_builder "cd '$build' && MAKEFLAGS=-j$(nproc) makepkg --noconfirm --cleanbuild"
secs=$(($(date +%s) - start))
df -h "$build"

nv=$(pb_eval 'echo "$pkgver-$pkgrel"')
kpkg=linux-t2-mbp161-$nv-x86_64.pkg.tar.zst
hpkg=linux-t2-mbp161-headers-$nv-x86_64.pkg.tar.zst
cp "$build/$kpkg" "$build/$hpkg" "$out/"
cd "$out"

kr=$(bsdtar -tf "$kpkg" | sed -n 's|^usr/lib/modules/\([^/]*\)/vmlinuz$|\1|p')
[[ -n $kr ]] || { echo "no vmlinuz in $kpkg" >&2; exit 1; }
# The modules the local patches change must be in the package.
for m in drivers/platform/x86/apple-gmux drivers/hid/hid-appletb-kbd \
  drivers/gpu/drm/tiny/appletbdrm drivers/gpu/drm/i915/i915 drivers/gpu/drm/amd/amdgpu/amdgpu \
  drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac drivers/bluetooth/btbcm \
  drivers/bluetooth/hci_uart drivers/bluetooth/hci_bcm4377; do
  bsdtar -tf "$kpkg" | grep -q "^usr/lib/modules/$kr/kernel/$m\.ko" ||
    { echo "missing module $m.ko in $kpkg" >&2; exit 1; }
done

sha256sum -- "$kpkg" "$hpkg" >SHA256SUMS
printf '%s\n' "$nv" >VERSION
printf '%s\n' "$inputs" >INPUTS
{
  echo "package        $nv"
  echo "kernelrelease  $kr"
  echo "toolbox commit ${GITHUB_SHA:-unknown}"
  echo "t2linux        $(pb_eval 'echo "$T2_PATCH_HASH"')"
  echo "kernel inputs  $inputs"
  echo "built          $(date -u +%Y-%m-%dT%H:%MZ) in ${secs}s on $(nproc) CPUs"
} >BUILDINFO.txt
cat SHA256SUMS BUILDINFO.txt
ls -l

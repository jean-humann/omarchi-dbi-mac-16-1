# Shareable pack. Sourced from bin/mbp16-1.
# Writes guide + toolbox only. Never copies private diary, logs, or cargo target.

_pack_helpers_identical() {
  cmp -s "$ROOT/scripts/mbp16-1-hypr-outputs" \
    "$FILES/home/.local/bin/mbp16-1-hypr-outputs" ||
    die "scripts/mbp16-1-hypr-outputs drifted from files/home/.local/bin/" \
      "files/ is canonical. Copy that helper into scripts/ before packing."
  cmp -s "$ROOT/scripts/mbp16-1-limine-quiet" \
    "$FILES/home/.local/bin/mbp16-1-limine-quiet" ||
    die "scripts/mbp16-1-limine-quiet drifted from files/home/.local/bin/" \
      "files/ is canonical. Copy that helper into scripts/ before packing."
}

_pack_list() {
  section "Share" "These paths are the public pack."
  hint "README.md  (.gitignore)  — README is the full install guide"
  hint "bin/  lib/  files/  kernel/  macos/  scripts/"
  hint "mbp16-1-powerd/  (source + Cargo.lock + unit + conf — not target/)"
  section "Leave out"
  hint "private diary, agent notes, incidents, logs/, .cursor/"
  hint "mbp16-1-powerd/target/"
  hint "keybags, catacomb archives, unredacted t2-touchid-doctor dumps"
}

_pack_gitignore() {
  cat <<'EOF'
# Private working-tree files — never commit even if copied here by mistake
CONTINUE.md
AGENTS.md
omarchy-mbp16-1-guide.md
MacBookPro16-1-Omarchy.md
incidents.md
yuters-issue-e77b03f.md
logs/
.cursor/
dist/

# Build / junk
mbp16-1-powerd/target/
**/__pycache__/
*.py[cod]
._*
.DS_Store

# Secrets
*.kb
*keybags*
*catacomb*
.env
.env.*
*.pem
id_rsa*
id_ed25519*
EOF
}

_pack_guide() {
  # Working tree keeps the guide as MacBookPro16-1-Omarchy.md so README.md can
  # stay the private doc map. The GitHub pack's README.md *is* that guide.
  if [[ -f $ROOT/MacBookPro16-1-Omarchy.md ]]; then
    printf '%s\n' "$ROOT/MacBookPro16-1-Omarchy.md"
  elif [[ -f $ROOT/README.md ]]; then
    printf '%s\n' "$ROOT/README.md"
  else
    die "no install guide" "need MacBookPro16-1-Omarchy.md or README.md"
  fi
}

_pack_stage() {
  local staging=$1 guide d
  guide=$(_pack_guide)
  mkdir -p "$staging"
  cp -a "$guide" "$staging/README.md"
  cp -a "$ROOT/bin" "$ROOT/lib" "$ROOT/files" "$ROOT/kernel" "$ROOT/macos" "$ROOT/scripts" "$staging/"
  mkdir -p "$staging/mbp16-1-powerd"
  cp -a "$ROOT/mbp16-1-powerd/Cargo.toml" "$ROOT/mbp16-1-powerd/Cargo.lock" \
    "$ROOT/mbp16-1-powerd/README.md" "$ROOT/mbp16-1-powerd/mbp16-1-powerd.conf" \
    "$ROOT/mbp16-1-powerd/mbp16-1-powerd.service" "$ROOT/mbp16-1-powerd/src" \
    "$ROOT/mbp16-1-powerd/.gitignore" "$staging/mbp16-1-powerd/"
  _pack_gitignore >"$staging/.gitignore"
  find "$staging" \( -name '._*' -o -name '.DS_Store' -o -name '*.py[co]' \) -delete
  while IFS= read -r d; do
    [[ -n $d ]] || continue
    rm -rf "$d"
  done < <(find "$staging" -type d -name '__pycache__' 2>/dev/null)
}

_pack_abs() {
  local p=$1
  [[ $p == /* ]] || p="$PWD/$p"
  printf '%s\n' "$p"
}

_pack_copy_tree() {
  local src=$1 dest=$2
  mkdir -p "$dest"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$src"/ "$dest/"
  else
    cp -a "$src"/. "$dest/"
  fi
}

# Write the shareable tree to $1. $2=1 force. $3=1 quiet (no section chrome).
_pack_write() {
  local dest=$1 force=${2:-0} quiet=${3:-0}
  local dest_abs staging is_git=0
  dest_abs=$(_pack_abs "$dest")
  [[ $dest_abs == "$ROOT" ]] && die "refusing to overwrite the working tree"
  [[ $ROOT == "$dest_abs"/* ]] && die "destination contains the working tree"

  is_git=0
  [[ -d $dest_abs/.git ]] && is_git=1

  if [[ -e $dest_abs && $is_git -eq 0 && $force -eq 0 ]]; then
    die "destination exists: $dest_abs" "remove it, pick another path, or pass --force"
  fi

  if ((DRY_RUN)); then
    if ((is_git)); then
      log "dry-run: would refresh git checkout $dest_abs" "keeps .git"
    elif [[ -e $dest_abs ]]; then
      log "dry-run: would replace $dest_abs"
    else
      log "dry-run: would write $dest_abs"
    fi
    return 0
  fi

  staging=$(mktemp -d)
  _pack_stage "$staging"

  if ((is_git)); then
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete --exclude .git "$staging"/ "$dest_abs/"
    else
      _pack_copy_tree "$staging" "$dest_abs"
    fi
    ((quiet)) || log "refreshed git checkout" "$dest_abs"
  else
    if [[ -e $dest_abs ]]; then
      rm -rf "$dest_abs"
    fi
    mkdir -p "$dest_abs"
    _pack_copy_tree "$staging" "$dest_abs"
  fi
  rm -rf "$staging"
  ((quiet)) || section "Wrote" "$dest_abs"
}

mbp16_1_pack() {
  local dest="" check=0 force=0 arg
  for arg in "$@"; do
    case $arg in
      --check) check=1 ;;
      --force) force=1 ;;
      --dry-run) ;;
      -*) die "unknown pack flag $arg" "use --check, --force, or a destination directory" ;;
      *)
        [[ -z $dest ]] || die "pack takes one destination" "got $dest and $arg"
        dest=$arg
        ;;
    esac
  done
  dest=${dest:-$ROOT/dist/$PACK_NAME}

  _pack_helpers_identical
  section "Check"
  ok "scripts/ helpers match files/"

  if ((check)); then
    _pack_list
    hint "would write  $dest"
    return 0
  fi

  if ((DRY_RUN)); then
    _pack_write "$dest" "$force" 0
    _pack_list
    return 0
  fi

  _pack_write "$dest" "$force" 0
  if [[ -d $(_pack_abs "$dest")/.git ]]; then
    hint "git checkout kept. Review git status, then commit."
  else
    hint "copy that directory onto the 16,1, or git init it. Not the private working tree."
  fi
}

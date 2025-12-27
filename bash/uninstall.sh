#!/usr/bin/env bash
# Uninstall the Bash hrid CLI and wordlists.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${PREFIX}/bin"
SHARE_DIR="${PREFIX}/share/human-readable-id"
XDG_SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/human-readable-id"

rm_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    rm -f "$path"
    echo "Removed $path"
  else
    echo "Not found: $path"
  fi
}

rmdir_if_empty() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    if rmdir "$dir" 2>/dev/null; then
      echo "Removed empty dir $dir"
    fi
  fi
}

main() {
  rm_if_exists "${BIN_DIR}/hrid"

  for dir in "$SHARE_DIR" "$XDG_SHARE_DIR"; do
    rm_if_exists "${dir}/predicates.txt"
    rm_if_exists "${dir}/objects.txt"
    rmdir_if_empty "$dir"
  done
}

main "$@"

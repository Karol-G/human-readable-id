#!/usr/bin/env bash
# Install the Bash hrid CLI and copy wordlists from the Python package data.

set -euo pipefail

PREFIX="${PREFIX:-"$HOME/.local"}"
BIN_DIR="${PREFIX}/bin"
SHARE_DIR="${PREFIX}/share/human-readable-id"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PY_WORDS="${ROOT_DIR}/human_readable_id/words"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/Karol-G/human-readable-id/main}"

err() { echo "Error: $*" >&2; exit 1; }

install_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

append_rc_export() {
  local export_line='export HRID_WORDS_DIR="$HOME/.local/share/human-readable-id"'
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc" ]] || continue
    if ! grep -Fq "$export_line" "$rc"; then
      printf '\n# Added by hrid installer\n%s\n' "$export_line" >> "$rc"
      echo "Added HRID_WORDS_DIR to $rc"
    fi
  done
}

download_to() {
  local url="$1" dst="$2"
  command -v curl >/dev/null 2>&1 || err "curl is required to download ${url}"
  mkdir -p "$(dirname "$dst")"
  curl -fsSL "$url" -o "$dst"
}

main() {
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  if [[ -x "${SCRIPT_DIR}/hrid.sh" ]]; then
    hrid_src="${SCRIPT_DIR}/hrid.sh"
  else
    hrid_src="${tmpdir}/hrid.sh"
    download_to "${BASE_URL}/bash/hrid.sh" "$hrid_src"
  fi

  if [[ -f "${PY_WORDS}/predicates.txt" && -f "${PY_WORDS}/objects.txt" ]]; then
    pred_src="${PY_WORDS}/predicates.txt"
    obj_src="${PY_WORDS}/objects.txt"
  else
    pred_src="${tmpdir}/predicates.txt"
    obj_src="${tmpdir}/objects.txt"
    download_to "${BASE_URL}/human_readable_id/words/predicates.txt" "$pred_src"
    download_to "${BASE_URL}/human_readable_id/words/objects.txt" "$obj_src"
  fi

  install_file "$hrid_src" "${BIN_DIR}/hrid"
  chmod +x "${BIN_DIR}/hrid"
  install_file "$pred_src" "${SHARE_DIR}/predicates.txt"
  install_file "$obj_src" "${SHARE_DIR}/objects.txt"

  echo "Installed hrid to ${BIN_DIR}/hrid"
  echo "Installed wordlists to ${SHARE_DIR}"
  append_rc_export
  echo 'To use immediately in this shell, run: export HRID_WORDS_DIR="$HOME/.local/share/human-readable-id"'
}

main "$@"

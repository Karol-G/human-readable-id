#!/usr/bin/env bash
# hrid - human-readable-id generator
#
# Generates IDs like:
#   predicate_object_42
#   predicate_object_deadbeef
#
# Word lists (one word per line) resolved from:
#   1) $HRID_WORDS_DIR if set
#   2) ${XDG_DATA_HOME:-$HOME/.local/share}/human-readable-id/
#   3) This script directory
#   4) Repo canonical human_readable_id/words/ (dev fallback)
# Files:
#   predicates.txt  - verbs/adjectives (predicates)
#   objects.txt     - nouns (direct objects)
#
# Features:
# - Optional positional SEED (any string). If provided:
#     - word choices are deterministic
#     - digit suffix (default mode) is deterministic
# - If no SEED is given:
#     - a random seed is generated internally
# - Configurable number of words: -w/--words N (default: 2)
#     - first N-1 words are predicates
#     - last word is an object
# - Configurable suffix length: -n/--numbers N (default: 3)
#     - default: N decimal digits derived deterministically from SEED
# - Optional --hash:
#     - suffix becomes hex of length N
#     - deterministic when a seed is provided; random otherwise
# - Configurable separator: -s/--separator SEP (default: "_")
# - Word trimming: -t/--trim N (default: 0 = no trimming)
#     - trims every word token (predicates + object) to at most N characters
#     - suffix is not trimmed
# - Optional --collision:
#     - does NOT generate an ID
#     - prints:
#         combinations_M: exact if safely printable (<= 2^53), else approx and/or "> 2^63-1"
#         n_for_Ecollision_1: similar reporting for n ~= ceil(sqrt(2M))
#     - uses awk log-space math (portable; avoids big-int / bc)
#
# Usage:
#   ./hrid [seed] [options]
#
set -euo pipefail

# ----------------------------
# Defaults
# ----------------------------
WORDS=2
NUMBERS=3
SEP="_"
TRIM=0
USE_HASH_SUFFIX=0
DO_COLLISION=0
USER_SEED_SET=0

# Paths
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
XDG_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"

# ----------------------------
# Helpers
# ----------------------------
usage() {
  cat <<'EOF'
hrid - human-readable-id generator

Usage:
  hrid [seed] [options]

Options:
  -w, --words N        Number of words in ID (default: 2).
                       First N-1 are predicates, last is an object.
  -n, --numbers N      Number of trailing digits/chars (default: 3).
  -s, --separator SEP  Separator between tokens (default: "_").
  -t, --trim N         Trim each word token to at most N characters (default: 0 = no trim).
      --hash           Use a hex hash suffix (length = -n); seeded runs are deterministic, unseeded are random.
      --collision      Print:
                         - combinations_M (exact if safely printable, else approx and/or "> 2^63-1")
                         - n_for_Ecollision_1 (same)
                       Then exit.
  -h, --help           Show this help.

Files (one word per line) expected next to this script:
  predicates.txt
  objects.txt
EOF
}

err() { echo "Error: $*" >&2; exit 1; }
is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Trim a word to at most N chars (ASCII-safe; your lists are lowercase ASCII).
# If N==0, returns the word unchanged.
trim_word() {
  local w="$1"
  local n="$2"
  if (( n > 0 )); then
    local trimmed="${w:0:n}"
    local pad=$(( n - ${#trimmed} ))
    if (( pad > 0 )); then
      printf '%s%0*d' "$trimmed" "$pad" 0
    else
      printf '%s' "$trimmed"
    fi
  else
    printf '%s' "$w"
  fi
}

# Portable-ish SHA256 hex of an input string
sha256_hex() {
  local s="$1"
  if have_cmd sha256sum; then
    printf '%s' "$s" | sha256sum | awk '{print $1}'
  elif have_cmd shasum; then
    printf '%s' "$s" | shasum -a 256 | awk '{print $1}'
  elif have_cmd openssl; then
    printf '%s' "$s" | openssl dgst -sha256 | awk '{print $2}'
  else
    err "Need sha256sum, shasum, or openssl for hashing"
  fi
}

# Read exactly L hex chars from /dev/urandom (L can be 0)
rand_hex_len() {
  local L="$1"
  if (( L <= 0 )); then printf ''; return 0; fi
  local bytes=$(( (L + 1) / 2 ))
  [[ -r /dev/urandom ]] || err "/dev/urandom not available"
  dd if=/dev/urandom bs=1 count="$bytes" 2>/dev/null \
    | od -An -tx1 | tr -d ' \n' | cut -c1-"$L"
}

# Deterministic hex string of length L derived from seed
seeded_hex_len() {
  local seed="$1" L="$2" out="" i=0 hx
  if (( L <= 0 )); then printf ''; return 0; fi
  while (( ${#out} < L )); do
    hx="$(sha256_hex "${seed}:hash:${i}")"
    out+="$hx"
    ((i++))
  done
  printf '%s' "${out:0:L}"
}

# Deterministic 32-bit integer from (seed, counter/tag)
# Uses sha256(seed:counter) and takes first 8 hex chars (32 bits)
rand_u32_from_seed() {
  local seed="$1" ctr="$2" hx
  hx="$(sha256_hex "${seed}:${ctr}")"
  echo $(( 16#${hx:0:8} ))
}

# Pick array element at idx modulo length
pick_from_array() {
  local -n arr="$1"
  local idx="$2"
  local len="${#arr[@]}"
  (( len > 0 )) || err "Internal: empty array"
  local j=$(( idx % len ))
  printf '%s' "${arr[$j]}"
}

# ----------------------------
# Parse arguments
# ----------------------------
SEED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--words)
      [[ $# -ge 2 ]] || err "Missing value for $1"
      WORDS="$2"; shift 2
      ;;
    -n|--numbers)
      [[ $# -ge 2 ]] || err "Missing value for $1"
      NUMBERS="$2"; shift 2
      ;;
    -s|--separator)
      [[ $# -ge 2 ]] || err "Missing value for $1"
      SEP="$2"; shift 2
      ;;
    -t|--trim)
      [[ $# -ge 2 ]] || err "Missing value for $1"
      TRIM="$2"; shift 2
      ;;
    --hash)
      USE_HASH_SUFFIX=1; shift
      ;;
    --collision)
      DO_COLLISION=1; shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    --)
      shift
      if [[ $# -gt 0 ]]; then
        [[ -z "$SEED" ]] || err "Only one positional seed is allowed"
        SEED="$1"; shift
      fi
      [[ $# -eq 0 ]] || err "Unexpected extra arguments: $*"
      ;;
    -*)
      err "Unknown option: $1"
      ;;
    *)
      [[ -z "$SEED" ]] || err "Only one positional seed is allowed (got extra: $1)"
      SEED="$1"; shift
      USER_SEED_SET=1
      ;;
  esac
done

is_uint "$WORDS"   || err "--words must be an unsigned integer"
is_uint "$NUMBERS" || err "--numbers must be an unsigned integer"
is_uint "$TRIM"    || err "--trim must be an unsigned integer"
(( WORDS >= 2 ))   || err "--words must be >= 2"
(( NUMBERS >= 0 )) || err "--numbers must be >= 0"
(( TRIM >= 0 ))    || err "--trim must be >= 0"

# ----------------------------
# Locate word files and counts
# ----------------------------
resolve_word_file() {
  local fname="$1"
  if [[ -n "${HRID_WORDS_DIR:-}" && -f "${HRID_WORDS_DIR}/${fname}" ]]; then
    echo "${HRID_WORDS_DIR}/${fname}"; return 0
  fi

  if [[ -f "${XDG_DATA_DIR}/human-readable-id/${fname}" ]]; then
    echo "${XDG_DATA_DIR}/human-readable-id/${fname}"; return 0
  fi

  if [[ -f "${SCRIPT_DIR}/${fname}" ]]; then
    echo "${SCRIPT_DIR}/${fname}"; return 0
  fi

  local repo_words="${ROOT_DIR}/human_readable_id/words"
  if [[ -f "${repo_words}/${fname}" ]]; then
    echo "${repo_words}/${fname}"; return 0
  fi

  err "Missing ${fname} (checked HRID_WORDS_DIR, XDG_DATA_HOME/default, script dir, repo canonical)"
}

PRED_FILE="$(resolve_word_file predicates.txt)"
OBJ_FILE="$(resolve_word_file objects.txt)"

PRED_N="$(wc -l < "$PRED_FILE" | tr -d '[:space:]')"
OBJ_N="$(wc -l < "$OBJ_FILE"  | tr -d '[:space:]')"
is_uint "$PRED_N" || err "Could not read predicates count"
is_uint "$OBJ_N"  || err "Could not read objects count"
(( PRED_N > 0 )) || err "predicates.txt is empty"
(( OBJ_N  > 0 )) || err "objects.txt is empty"

# ============================================================
# --collision mode: overflow-safe using awk log-space math
# ============================================================
if (( DO_COLLISION == 1 )); then
  awk -v P="$PRED_N" -v O="$OBJ_N" -v W="$WORDS" -v N="$NUMBERS" -v H="$USE_HASH_SUFFIX" '
    function log10(x) { return log(x)/log(10) }

    # Build "≈ a.eK" from log10 value
    function sci_from_log10(lg,    k, frac, a) {
      if (lg < 0) return "≈ 0"
      k = int(lg)
      frac = lg - k
      a = exp(frac * log(10))  # in [1,10)
      return sprintf("≈ %.3ge%d", a, k)
    }

    function ceil_real(x) { return (x == int(x)) ? x : int(x) + 1 }

    BEGIN{
      # Constants:
      # - max signed 64-bit ~ 9.22e18
      # - max EXACT integer representable in IEEE-754 double is 2^53
      i64max = 9223372036854775807
      lg_i64max = log10(i64max)
      dbl_exact_max = 9007199254740992  # 2^53

      # suffix log10 space
      suffix_lg = 0
      if (N == 0) {
        suffix_lg = 0
      } else if (H == 1) {
        suffix_lg = N * log10(16)
      } else {
        suffix_lg = N * log10(10) # = N
      }

      # log10(M) where:
      #   M = (P)^(W-1) * (O) * suffix_space
      M_lg = (W-1)*log10(P) + log10(O) + suffix_lg

      # Print config
      printf("predicates: %d\n", P)
      printf("objects:    %d\n", O)
      printf("words:      %d (predicates=%d, objects=1)\n", W, W-1)
      if (N == 0) {
        printf("suffix:     none\n\n")
      } else if (H == 1) {
        printf("suffix:     hex hash length %d (space=16^%d)\n\n", N, N)
      } else {
        printf("suffix:     digits length %d (space=10^%d)\n\n", N, N)
      }

      # combinations_M
      if (M_lg > lg_i64max) {
        printf("combinations_M: %s\n", sci_from_log10(M_lg))
        printf("combinations_M: > 2^63-1\n")
      } else {
        # M fits in signed 64-bit. Print exact only if also <= 2^53 to avoid rounding lies.
        M = exp(M_lg * log(10))
        if (M <= dbl_exact_max) {
          printf("combinations_M: %.0f\n", M)
        } else {
          printf("combinations_M: %s (< 2^63-1)\n", sci_from_log10(M_lg))
        }
      }

      # n for expected collision of 1: n ~= ceil(sqrt(2M))
      # log10(n) = 0.5*(log10(M)+log10(2))
      n_lg = 0.5 * (M_lg + log10(2))

      if (n_lg > lg_i64max) {
        printf("n_for_Ecollision_1: %s\n", sci_from_log10(n_lg))
        printf("n_for_Ecollision_1: > 2^63-1\n")
      } else {
        n = exp(n_lg * log(10))
        if (n <= dbl_exact_max) {
          printf("n_for_Ecollision_1: %.0f\n", ceil_real(n))
        } else {
          printf("n_for_Ecollision_1: %s (< 2^63-1)\n", sci_from_log10(n_lg))
        }
      }

      printf("\n")
      printf("Notes:\n")
      printf("- combinations_M is the total number of distinct human-readable-ids possible with the current settings.\n")
      printf("- \"≈ X.YZeK\" means the value is shown in scientific notation because it is too large\n")
      printf("  to be represented exactly without arbitrary-precision arithmetic.\n")
      printf("- \"> 2^63-1\" means the value exceeds the maximum signed 64-bit integer and therefore\n")
      printf("  cannot be printed exactly using native integer arithmetic.\n")
      printf("- n_for_Ecollision_1 is the approximate number of generated human-readable-ids at which the expected\n")
      printf("  number of collisions reaches 1 (birthday paradox approximation).\n")
    }
  '
  exit 0
fi

# ============================================================
# Normal ID generation
# ============================================================

# Load word lists for generation
mapfile -t PREDICATES < "$PRED_FILE"
mapfile -t OBJECTS    < "$OBJ_FILE"

# Determine seed (random if not provided)
if [[ -z "${SEED:-}" ]]; then
  SEED="$(rand_hex_len 32)"
fi

TOKENS=()

# N-1 predicates
for ((i=0; i<WORDS-1; i++)); do
  r="$(rand_u32_from_seed "$SEED" "pred:$i")"
  w="$(pick_from_array PREDICATES "$r")"
  TOKENS+=("$(trim_word "$w" "$TRIM")")
done

# Final object
r="$(rand_u32_from_seed "$SEED" "obj")"
w="$(pick_from_array OBJECTS "$r")"
TOKENS+=("$(trim_word "$w" "$TRIM")")

# Suffix
SUFFIX=""
if (( NUMBERS > 0 )); then
  if (( USE_HASH_SUFFIX == 1 )); then
    if (( USER_SEED_SET == 1 )); then
      SUFFIX="$(seeded_hex_len "$SEED" "$NUMBERS")"
    else
      SUFFIX="$(rand_hex_len "$NUMBERS")"
    fi
  else
    # Deterministic digits derived from seed
    digits=""
    for ((i=0; i<NUMBERS; i++)); do
      r="$(rand_u32_from_seed "$SEED" "num:$i")"
      digits+="$(( r % 10 ))"
    done
    SUFFIX="$digits"
  fi
fi

# Join tokens with separator
out=""
for t in "${TOKENS[@]}"; do
  if [[ -z "$out" ]]; then
    out="$t"
  else
    out="${out}${SEP}${t}"
  fi
done

if [[ -n "$SUFFIX" ]]; then
  out="${out}${SEP}${SUFFIX}"
fi

printf '%s\n' "$out"

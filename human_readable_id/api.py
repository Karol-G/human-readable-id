"""Python implementation of the readable-id generator."""

from __future__ import annotations

import hashlib
import math
import secrets
from pathlib import Path
from typing import Iterable


DATA_DIR = Path(__file__).resolve().parent / "words"
I64_MAX = 9_223_372_036_854_775_807
DBL_EXACT_MAX = 9_007_199_254_740_992  # 2**53


class HridError(Exception):
    """Raised when HRID generation cannot proceed."""


def _read_words(path: Path) -> list[str]:
    if not path.is_file():
        raise HridError(f"Missing wordlist: {path}")
    words = [line.rstrip("\n") for line in path.read_text(encoding="utf-8").splitlines()]
    if not words:
        raise HridError(f"Wordlist is empty: {path}")
    return words


def _sha256_hex(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def _rand_u32_from_seed(seed: str, tag: str) -> int:
    hx = _sha256_hex(f"{seed}:{tag}")
    return int(hx[:8], 16)


def _rand_hex_len(length: int) -> str:
    if length <= 0:
        return ""
    # token_hex takes n bytes and returns 2n hex chars; trim in case of odd lengths.
    chars_needed = length
    bytes_needed = (chars_needed + 1) // 2
    return secrets.token_hex(bytes_needed)[:chars_needed]


def _seeded_hex_len(seed: str, length: int) -> str:
    """Deterministic hex string of given length from seed."""
    if length <= 0:
        return ""
    out = ""
    i = 0
    while len(out) < length:
        hx = _sha256_hex(f"{seed}:hash:{i}")
        out += hx
        i += 1
    return out[:length]



def _trim_word(word: str, limit: int) -> str:
    if limit <= 0:
        return word
    return word[:limit]


def generate_hrid(
    seed: str | None = None,
    *,
    words: int = 2,
    numbers: int = 3,
    separator: str = "_",
    trim: int = 0,
    use_hash_suffix: bool = False,
    predicates_path: Path | None = None,
    objects_path: Path | None = None,
) -> str:
    """Generate a readable-id matching the Bash implementation."""
    if words < 2:
        raise HridError("--words must be >= 2")
    if numbers < 0:
        raise HridError("--numbers must be >= 0")
    if trim < 0:
        raise HridError("--trim must be >= 0")

    pred_path = predicates_path or (DATA_DIR / "predicates.txt")
    obj_path = objects_path or (DATA_DIR / "objects.txt")

    predicates = _read_words(pred_path)
    objects = _read_words(obj_path)

    use_seed = seed or _rand_hex_len(32)
    user_seed = seed is not None

    tokens: list[str] = []
    for idx in range(words - 1):
        r = _rand_u32_from_seed(use_seed, f"pred:{idx}")
        w = predicates[r % len(predicates)]
        tokens.append(_trim_word(w, trim))

    r = _rand_u32_from_seed(use_seed, "obj")
    w = objects[r % len(objects)]
    tokens.append(_trim_word(w, trim))

    suffix = ""
    if numbers > 0:
        if use_hash_suffix:
            if user_seed:
                suffix = _seeded_hex_len(use_seed, numbers)
            else:
                suffix = _rand_hex_len(numbers)
        else:
            digits = []
            for idx in range(numbers):
                r = _rand_u32_from_seed(use_seed, f"num:{idx}")
                digits.append(str(r % 10))
            suffix = "".join(digits)

    out = separator.join(tokens)
    if suffix:
        out = f"{out}{separator}{suffix}"
    return out


def _sci_from_log10(log10_val: float) -> str:
    if log10_val < 0:
        return "≈ 0"
    k = int(log10_val)
    frac = log10_val - k
    a = math.exp(frac * math.log(10))
    return f"≈ {a:.3g}e{k}"


def collision_report(
    *,
    words_count: int,
    numbers: int,
    use_hash_suffix: bool,
    predicates_len: int,
    objects_len: int,
) -> str:
    """Compute collision/capacity report matching the Bash awk output."""
    if words_count < 2:
        raise HridError("--words must be >= 2")
    if numbers < 0:
        raise HridError("--numbers must be >= 0")
    if predicates_len <= 0 or objects_len <= 0:
        raise HridError("Wordlists must not be empty")

    lg_16 = math.log10(16)
    lg_10 = math.log10(10)

    if numbers == 0:
        suffix_lg = 0.0
    elif use_hash_suffix:
        suffix_lg = numbers * lg_16
    else:
        suffix_lg = numbers * lg_10

    m_lg = (words_count - 1) * math.log10(predicates_len) + math.log10(objects_len) + suffix_lg

    lines: list[str] = []
    lines.append(f"predicates: {predicates_len}")
    lines.append(f"objects:    {objects_len}")
    lines.append(f"words:      {words_count} (predicates={words_count - 1}, objects=1)")
    if numbers == 0:
        lines.append("suffix:     none")
    elif use_hash_suffix:
        lines.append(f"suffix:     hex hash length {numbers} (space=16^{numbers})")
    else:
        lines.append(f"suffix:     digits length {numbers} (space=10^{numbers})")
    lines.append("")

    if m_lg > math.log10(I64_MAX):
        lines.append(f"combinations_M: {_sci_from_log10(m_lg)}")
        lines.append("combinations_M: > 2^63-1")
    else:
        m_val = math.exp(m_lg * math.log(10))
        if m_val <= DBL_EXACT_MAX:
            lines.append(f"combinations_M: {m_val:.0f}")
        else:
            lines.append(f"combinations_M: {_sci_from_log10(m_lg)} (< 2^63-1)")

    n_lg = 0.5 * (m_lg + math.log10(2))
    if n_lg > math.log10(I64_MAX):
        lines.append(f"n_for_Ecollision_1: {_sci_from_log10(n_lg)}")
        lines.append("n_for_Ecollision_1: > 2^63-1")
    else:
        n_val = math.exp(n_lg * math.log(10))
        if n_val <= DBL_EXACT_MAX:
            n_int = int(n_val) if n_val == int(n_val) else int(n_val) + 1
            lines.append(f"n_for_Ecollision_1: {n_int:.0f}")
        else:
            lines.append(f"n_for_Ecollision_1: {_sci_from_log10(n_lg)} (< 2^63-1)")

    lines.append("")
    lines.append("Notes:")
    lines.append("- combinations_M is the total number of distinct readable-ids possible with the current settings.")
    lines.append('- "≈ X.YZeK" means the value is shown in scientific notation because it is too large')
    lines.append("  to be represented exactly without arbitrary-precision arithmetic.")
    lines.append('- "> 2^63-1" means the value exceeds the maximum signed 64-bit integer and therefore')
    lines.append("  cannot be printed exactly using native integer arithmetic.")
    lines.append("- n_for_Ecollision_1 is the approximate number of generated readable-ids at which the expected")
    lines.append("  number of collisions reaches 1 (birthday paradox approximation).")
    return "\n".join(lines)


def collision_report_from_files(
    *,
    words_count: int,
    numbers: int,
    use_hash_suffix: bool,
    predicates_path: Path | None = None,
    objects_path: Path | None = None,
) -> str:
    pred_path = predicates_path or (DATA_DIR / "predicates.txt")
    obj_path = objects_path or (DATA_DIR / "objects.txt")
    preds = _read_words(pred_path)
    objs = _read_words(obj_path)
    return collision_report(
        words_count=words_count,
        numbers=numbers,
        use_hash_suffix=use_hash_suffix,
        predicates_len=len(preds),
        objects_len=len(objs),
    )

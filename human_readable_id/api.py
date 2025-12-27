"""Python implementation of the human-readable-id generator."""

from __future__ import annotations

import hashlib
import math
import secrets
from pathlib import Path
from typing import Iterable


DATA_DIR = Path(__file__).resolve().parent / "words"


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
    trimmed = word[:limit]
    if len(trimmed) < limit:
        trimmed = trimmed + ("0" * (limit - len(trimmed)))
    return trimmed


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
    """Generate a human-readable-id matching the Bash implementation."""
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


def _collision_threshold_for_expected_one(space_size: int) -> int:
    """Smallest n such that n(n-1)/2 >= space_size."""
    if space_size <= 0:
        return 0
    discriminant = 1 + 8 * space_size
    root = math.isqrt(discriminant)
    if root * root < discriminant:
        root += 1
    return (root + 2) // 2


def _fmt_int(n: int) -> str:
    """Readable formatting with thousand separators."""
    return f"{n:,}"


def collision_report(
    *,
    words_count: int,
    numbers: int,
    use_hash_suffix: bool,
    predicates_len: int,
    objects_len: int,
) -> str:
    """Compute collision/capacity report with exact integer arithmetic."""
    if words_count < 2:
        raise HridError("--words must be >= 2")
    if numbers < 0:
        raise HridError("--numbers must be >= 0")
    if predicates_len <= 0 or objects_len <= 0:
        raise HridError("Wordlists must not be empty")

    suffix_space = 1
    if numbers > 0:
        base = 16 if use_hash_suffix else 10
        suffix_space = base**numbers

    combinations = (predicates_len ** (words_count - 1)) * objects_len * suffix_space
    collision_threshold = _collision_threshold_for_expected_one(combinations)

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

    lines.append(f"combinations_M: {_fmt_int(combinations)}")
    lines.append(f"n_for_Ecollision_1: {_fmt_int(collision_threshold)}")

    lines.append("")
    lines.append("Notes:")
    lines.append("- combinations_M is the total number of distinct human-readable-ids possible with the current settings.")
    lines.append("- values are computed exactly using integer arithmetic (no floating-point truncation).")
    lines.append("- n_for_Ecollision_1 is the smallest number of generated human-readable-ids where expected collisions reach 1.")
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

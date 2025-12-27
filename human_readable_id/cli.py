"""Command-line entrypoint for human-readable-id."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .api import HridError, collision_report_from_files, generate_hrid


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="hrid",
        description="human-readable-id generator (Python) mirroring the Bash implementation.",
    )
    parser.add_argument("seed", nargs="?", help="Optional seed for deterministic output.")
    parser.add_argument("-w", "--words", type=int, default=2, help="Number of words (default: 2).")
    parser.add_argument(
        "-n",
        "--numbers",
        type=int,
        default=3,
        help="Number of trailing digits/chars (default: 3).",
    )
    parser.add_argument(
        "-s",
        "--separator",
        default="_",
        help='Separator between tokens (default: "_").',
    )
    parser.add_argument(
        "-t",
        "--trim",
        type=int,
        default=0,
        help="Trim each word to at most N characters (default: 0 = no trim).",
    )
    parser.add_argument(
        "--hash",
        action="store_true",
        dest="use_hash_suffix",
        help="Use a hex suffix (length = --numbers); seeded runs are deterministic, unseeded are random.",
    )
    parser.add_argument(
        "--collision",
        action="store_true",
        help="Print combinations and collision threshold instead of generating an ID.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    try:
        if args.collision:
            report = collision_report_from_files(
                words_count=args.words,
                numbers=args.numbers,
                use_hash_suffix=args.use_hash_suffix,
            )
            sys.stdout.write(f"{report}\n")
            return 0

        out = generate_hrid(
            seed=args.seed,
            words=args.words,
            numbers=args.numbers,
            separator=args.separator,
            trim=args.trim,
            use_hash_suffix=args.use_hash_suffix,
        )
        sys.stdout.write(f"{out}\n")
        return 0
    except HridError as exc:
        sys.stderr.write(f"Error: {exc}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

<h1>
  <img src="hrid.png" alt="hrid logo" width="34" />
  <big>Human Readable ID</big>
</h1>

![PyPI](https://img.shields.io/pypi/v/human-readable-id?logo=pypi&color=brightgreen)
![Python Version](https://img.shields.io/pypi/pyversions/human-readable-id?logo=python)
![Tests](https://img.shields.io/github/actions/workflow/status/Karol-G/human-readable-id/workflow.yml?branch=main&logo=github)
![Copier Template](https://img.shields.io/badge/copier-template-blue?logo=jinja)
![License](https://img.shields.io/github/license/Karol-G/human-readable-id)

Human Readable ID (hrid) generates short, human-readable, collision-aware, friendly IDs that are ideal for experiments, jobs, and filenames.

## Why human-readable-id?

Traditional IDs (UUIDs, hashes) are:

* hard to read
* hard to remember
* hard to communicate
* unpleasant in logs, filenames, and UIs

human-readable-id produces identifiers like:

```
gentle_river_42
silent_orbit_a9f3c2d1
```

They are:

* readable
* easy to communicate
* deterministic when seeded
* configurable for collision safety

## Features

* Predicate–object word structure for human readable IDs
* Friendly words only
* Deterministic generation from a seed
* Configurable number of words and suffix length
* Optional hash-based suffixes
* Collision-space analysis (`--collision`)
* Word trimming for predictable ID length
* Implementations in **Bash** and **Python**
* No sudo required, HPC-readable

## Installation

### Python

You can install human-readable-id via [pip](https://pypi.org/project/human-readable-id/) (also includes CLI commands):
```bash
pip install human-readable-id
```

### Bash (CLI)

The pure Bash version installs the `hrid` command and wordlists locally (no sudo) and does not require Python:

```bash
curl -fsSL "https://raw.githubusercontent.com/Karol-G/human-readable-id/main/bash/install.sh" | bash
```

This installs:

* Binary: `~/.local/bin/hrid`
* Wordlists: `~/.local/share/human-readable-id/` (copied from the Python package’s canonical lists)

Make sure `~/.local/bin` is on your `$PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

### CLI (Both Python and Bash)

Generate a human readable ID:

```bash
hrid # elastic_jargon_503, medieval_chess_277, nine_crayfish_660
```

Deterministic ID from a seed:

```bash
hrid my_seed # calm_menu_496
```

Use more words and a hash suffix:

```bash
hrid -w 3 -n 8 --hash # various_elegant_museum_2a750add
```

With a seed, the hash suffix is deterministic; without a seed it is random.

Trim words to enforce predictable length:

```bash
hrid -t 4 # clim_figu_144
```

Analyze collision space instead of generating an ID:

```bash
hrid --collision # scalloped_wombat_617

# predicates: 1450
# objects:    3062
# words:      2 (predicates=1, objects=1)
# suffix:     digits length 3 (space=10^3)
# combinations_M: 4439900000
# n_for_Ecollision_1: 94233

hrid -n 8 --hash --collision # distinct_sphere_3f9b7140

# predicates: 1450
# objects:    3062
# words:      2 (predicates=1, objects=1)
# suffix:     hex hash length 8 (space=16^8)
# combinations_M: ≈ 1,91e16 (< 2^63-1)
# n_for_Ecollision_1: 195290683
```

### Python API

Basic usage:

```python
from human_readable_id import generate_hrid

generate_hrid() # alert_tarn_100
```

Deterministic generation:

```python
generate_hrid(seed="my_seed") # calm_menu_496
```

Custom configuration:

```python
generate_hrid(
    seed="experiment-001",
    words=3,
    numbers=8,
    use_hash_suffix=True,
    trim=4,
) # nerv_oval_batt_c8597bc1
```

## Collision awareness

human-readable-id explicitly exposes the size of its ID space.

Using `--collision` (or the Python equivalent) reports:

* total number of possible IDs (exact)
* smallest number of generated IDs needed for an *expected* collision of 1 (exact)

The Python implementation computes these values with integer arithmetic (no rounding); the Bash CLI falls back to approximate formatting for extremely large spaces.

This helps choose safe parameters instead of guessing.

## Wordlists

IDs are built from curated wordlists:

* **predicates** (verbs / adjectives)
* **objects** (nouns)

Canonical wordlists live in `python/src/human_readable_id/words/` and ship with the Python package. The Bash installer copies those same files into `~/.local/share/human-readable-id/` for the CLI. Update the canonical files and rerun the installer (or copy them manually) if you want custom lists.

## Contributing

Contributions are welcome! Please open a pull request with clear changes and add tests when appropriate.

## Issues

Found a bug or have a request? Open an issue at https://github.com/Karol-G/human-readable-id/issues.

## License

Distributed under the MIT license. See `LICENSE` for details.

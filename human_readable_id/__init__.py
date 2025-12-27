"""Human Readable ID (hrid) generates short, human-readable, collision-aware, friendly IDs that are ideal for experiments, jobs, and filenames.."""

from importlib import metadata as _metadata

__all__ = [
    "__version__",
    "HridError",
    "collision_report_from_files",
    "generate_hrid",
    "collision_report",
]

try:
    __version__ = _metadata.version(__name__)
except _metadata.PackageNotFoundError:  # pragma: no cover - during editable installs pre-build
    __version__ = "0.0.0"

from .api import HridError, collision_report_from_files, generate_hrid, collision_report

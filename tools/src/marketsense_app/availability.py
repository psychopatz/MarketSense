"""Public availability contracts and acquisition-index facade."""

from .availability_model import (
    AVAILABILITY_FILTERS,
    CHANNEL_LABELS,
    AcquisitionEvidence,
    AvailabilityIndex,
    availability_counts,
    availability_matches,
    normalize_availability_filter,
)
from .availability_scan import build_acquisition_index

__all__ = [
    "AVAILABILITY_FILTERS",
    "CHANNEL_LABELS",
    "AcquisitionEvidence",
    "AvailabilityIndex",
    "availability_counts",
    "availability_matches",
    "build_acquisition_index",
    "normalize_availability_filter",
]

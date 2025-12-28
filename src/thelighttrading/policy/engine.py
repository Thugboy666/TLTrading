from __future__ import annotations

from dataclasses import dataclass
from typing import List

from ..config.settings import get_settings
from ..protocols.schemas import Strategy
from ..protocols.signing import compute_hash


@dataclass
class PolicyDecision:
    allow: bool
    reasons: List[str]


def load_policy_text() -> str:
    return get_settings().policy_text


def compute_policy_hash() -> str:
    return compute_hash({"policy_text": load_policy_text()})


def evaluate_strategy(strategy: Strategy) -> PolicyDecision:
    reasons: List[str] = []
    entries = strategy.entries or []

    if not entries:
        reasons.append("no_entries")
    if len(entries) > 5:
        reasons.append("too_many_entries")

    for entry in entries:
        if entry.size <= 0:
            reasons.append(f"non_positive_size:{entry.ticker}")
        if entry.size > 5:
            reasons.append(f"oversized:{entry.ticker}")
        if entry.direction not in {"long", "short"}:
            reasons.append(f"bad_direction:{entry.ticker}")

    allow = len(reasons) == 0
    return PolicyDecision(allow=allow, reasons=reasons)

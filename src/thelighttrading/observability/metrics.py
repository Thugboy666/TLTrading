from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict


@dataclass
class Metrics:
    runs_total: int = 0
    runs_ok: int = 0
    runs_blocked: int = 0
    llm_calls_total: int = 0
    executions_total: int = 0
    _llm_latency_buckets: Dict[str, int] = field(default_factory=lambda: {"lt1": 0, "lt3": 0, "lt10": 0, "gt10": 0})

    def observe_llm_latency(self, seconds: float) -> None:
        if seconds < 1:
            self._llm_latency_buckets["lt1"] += 1
        elif seconds < 3:
            self._llm_latency_buckets["lt3"] += 1
        elif seconds < 10:
            self._llm_latency_buckets["lt10"] += 1
        else:
            self._llm_latency_buckets["gt10"] += 1

    def snapshot(self) -> dict:
        return {
            "runs_total": self.runs_total,
            "runs_ok": self.runs_ok,
            "runs_blocked": self.runs_blocked,
            "llm_calls_total": self.llm_calls_total,
            "executions_total": self.executions_total,
            "llm_latency_buckets": dict(self._llm_latency_buckets),
        }


metrics = Metrics()

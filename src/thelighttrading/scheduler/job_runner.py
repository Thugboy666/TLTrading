from __future__ import annotations

import time

from ..nodes.orchestrator import Orchestrator


def run_loop(interval_seconds: int = 60, once: bool = False) -> None:
    orch = Orchestrator()
    while True:
        orch.run_pipeline()
        if once:
            break
        time.sleep(interval_seconds)

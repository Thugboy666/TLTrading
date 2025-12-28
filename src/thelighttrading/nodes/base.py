import time
from dataclasses import dataclass
from typing import Any, Dict
from ..llm_router import router
from ..memory.node_memory import remember


@dataclass
class NodeResult:
    node_id: str
    output: Dict[str, Any]
    ts_start: float
    ts_end: float


class BaseNode:
    id: str
    name: str
    profile: str

    def __init__(self, node_id: str, name: str, profile: str):
        self.id = node_id
        self.name = name
        self.profile = profile

    def run(self, messages: list[dict]) -> NodeResult:
        ts_start = time.time()
        raw = router.generate(self.profile, messages)
        output = self.postprocess(raw)
        ts_end = time.time()
        remember(self.id, "last", output, ts_end)
        return NodeResult(node_id=self.id, output=output, ts_start=ts_start, ts_end=ts_end)

    def postprocess(self, raw: str) -> Dict[str, Any]:
        raise NotImplementedError

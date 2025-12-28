import time
from dataclasses import dataclass
from typing import Any, Dict
from ..llm_router import router
from ..memory.node_memory import remember


@dataclass
class NodeResult:
    node_id: str
    output: Dict[str, Any]
    ts: float


class BaseNode:
    id: str
    name: str
    profile: str

    def __init__(self, node_id: str, name: str, profile: str):
        self.id = node_id
        self.name = name
        self.profile = profile

    def run(self, messages: list[dict]) -> NodeResult:
        ts = time.time()
        raw = router.generate(self.profile, messages)
        output = self.postprocess(raw)
        remember(self.id, "last", output, ts)
        return NodeResult(node_id=self.id, output=output, ts=ts)

    def postprocess(self, raw: str) -> Dict[str, Any]:
        raise NotImplementedError

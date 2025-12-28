import json
from pydantic import ValidationError
from .base import BaseNode
from .registry import register_node
from ..protocols.schemas import WatchdogDecision


@register_node("watchdog")
class WatchdogNode(BaseNode):
    def __init__(self):
        super().__init__("watchdog", "WatchdogNode", "watchdog_phi")

    def postprocess(self, raw: str):
        try:
            data = json.loads(raw)
            model = WatchdogDecision.model_validate(data)
            return model.model_dump()
        except (json.JSONDecodeError, ValidationError):
            return {"block": True, "reasons": ["invalid_watchdog"], "risk": "unknown", "error": "invalid_watchdog"}

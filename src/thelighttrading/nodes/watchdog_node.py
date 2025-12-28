import json
from .base import BaseNode


class WatchdogNode(BaseNode):
    def __init__(self):
        super().__init__("watchdog", "WatchdogNode", "watchdog_phi")

    def postprocess(self, raw: str):
        try:
            data = json.loads(raw)
            if "block" not in data:
                data["block"] = True
            return data
        except json.JSONDecodeError:
            return {"block": True, "reasons": ["invalid json"], "raw": raw}

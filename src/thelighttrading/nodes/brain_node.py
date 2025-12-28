import json
from .base import BaseNode


class BrainNode(BaseNode):
    def __init__(self):
        super().__init__("brain", "BrainNode", "brain_mistral")

    def postprocess(self, raw: str):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {"entries": [], "error": "invalid json", "raw": raw}

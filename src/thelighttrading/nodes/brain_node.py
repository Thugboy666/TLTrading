import json
from pydantic import ValidationError
from .base import BaseNode
from ..protocols.schemas import Strategy


class BrainNode(BaseNode):
    def __init__(self):
        super().__init__("brain", "BrainNode", "brain_mistral")

    def postprocess(self, raw: str):
        try:
            data = json.loads(raw)
            model = Strategy.model_validate(data)
            return model.model_dump()
        except (json.JSONDecodeError, ValidationError):
            return {"entries": [], "rationale": "", "horizon_minutes": 0, "error": "invalid_strategy"}

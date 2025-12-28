import json
from pydantic import ValidationError
from .base import BaseNode
from ..protocols.schemas import Signals


class ParserNode(BaseNode):
    def __init__(self):
        super().__init__("parser", "ParserNode", "parser_qwen")

    def postprocess(self, raw: str):
        try:
            data = json.loads(raw)
            model = Signals.model_validate(data)
            return model.model_dump()
        except (json.JSONDecodeError, ValidationError):
            return {"signals": [], "error": "invalid_signals"}

import json
from .base import BaseNode


class ParserNode(BaseNode):
    def __init__(self):
        super().__init__("parser", "ParserNode", "parser_qwen")

    def postprocess(self, raw: str):
        try:
            data = json.loads(raw)
            if "signals" not in data:
                data["signals"] = []
            return data
        except json.JSONDecodeError:
            return {"signals": [], "error": "invalid json", "raw": raw}

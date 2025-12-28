import json
from .base import BaseNode


class NewsNode(BaseNode):
    def __init__(self):
        super().__init__("news", "NewsNode", "news_llama")

    def postprocess(self, raw: str):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {"error": "invalid json", "raw": raw}

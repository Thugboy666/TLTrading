import json
from pydantic import ValidationError
from .base import BaseNode
from .registry import register_node
from ..protocols.schemas import NewsBrief


@register_node("news")
class NewsNode(BaseNode):
    def __init__(self):
        super().__init__("news", "NewsNode", "news_llama")

    def postprocess(self, raw: str):
        try:
            data = json.loads(raw)
            model = NewsBrief.model_validate(data)
            return model.model_dump()
        except (json.JSONDecodeError, ValidationError):
            return {"ticker": "", "sentiment": "unknown", "summary": "", "error": "invalid_news"}

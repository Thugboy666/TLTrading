import json


def mock_generate(profile: str, messages, temperature: float, max_tokens: int) -> str:
    if profile == "news_llama":
        return json.dumps({"ticker": "XYZ", "sentiment": "positive", "summary": "Mock summary"})
    if profile == "parser_qwen":
        return json.dumps({"signals": [{"ticker": "XYZ", "action": "buy", "confidence": 0.9}]})
    if profile == "brain_mistral":
        return json.dumps({
            "entries": [{"ticker": "XYZ", "direction": "long", "size": 1.0}],
            "rationale": "Mock rationale",
            "horizon_minutes": 30,
        })
    if profile == "watchdog_phi":
        return json.dumps({"block": False, "reasons": [], "risk": "low"})
    return "{}"

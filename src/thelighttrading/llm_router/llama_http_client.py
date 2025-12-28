import requests
from ..config.settings import get_settings


def post_completion(messages, temperature=0.2, max_tokens=512):
    settings = get_settings()
    url = f"{settings.llm_base_url.rstrip('/')}/v1/chat/completions"
    payload = {
        "model": "auto",
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    resp = requests.post(url, json=payload, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    return data.get("choices", [{}])[0].get("message", {}).get("content", "")

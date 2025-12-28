import requests
from ..config.settings import get_settings


def is_server_available() -> bool:
    settings = get_settings()
    url = f"{settings.llm_base_url.rstrip('/')}/v1/models"
    try:
        resp = requests.get(url, timeout=1)
        resp.raise_for_status()
        return True
    except requests.RequestException:
        return False


def post_completion(messages, temperature=0.2, max_tokens=512):
    settings = get_settings()
    url = f"{settings.llm_base_url.rstrip('/')}/v1/chat/completions"
    payload = {
        "model": "auto",
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    last_exc = None
    for attempt in range(2):
        try:
            resp = requests.post(url, json=payload, timeout=10)
            resp.raise_for_status()
            data = resp.json()
            return data.get("choices", [{}])[0].get("message", {}).get("content", "")
        except requests.RequestException as exc:
            last_exc = exc
            if attempt == 1:
                raise
    if last_exc:
        raise last_exc
    return ""

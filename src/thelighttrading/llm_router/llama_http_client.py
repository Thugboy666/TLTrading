import requests
from ..config.settings import get_settings


def get_base_url(settings=None) -> str:
    settings = settings or get_settings()
    if settings.llm_mode == "local":
        host = settings.llm_host or "127.0.0.1"
        port = settings.llm_port or 8081
        return f"http://{host}:{port}"
    return settings.llm_base_url


def is_server_available(base_url: str | None = None) -> bool:
    ok, _ = get_server_health(base_url)
    return ok


def get_server_health(base_url: str | None = None) -> tuple[bool, str | None]:
    if base_url is None:
        base_url = get_base_url()
    url = f"{base_url.rstrip('/')}/v1/models"
    try:
        resp = requests.get(url, timeout=1)
    except requests.RequestException as exc:
        return False, f"{type(exc).__name__}: {exc}"
    if resp.status_code >= 400:
        detail = resp.text.strip()
        if detail:
            detail = detail[:300]
            return False, f"HTTP {resp.status_code} {resp.reason}: {detail}"
        return False, f"HTTP {resp.status_code} {resp.reason}"
    return True, None


def post_completion(messages, temperature=0.2, max_tokens=512, base_url: str | None = None):
    if base_url is None:
        base_url = get_base_url()
    url = f"{base_url.rstrip('/')}/v1/chat/completions"
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

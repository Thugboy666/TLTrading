import requests

from ..config.settings import Settings


def _base_url(settings: Settings) -> str:
    return settings.llm_base_url or f"http://{settings.llm_host}:{settings.llm_port}"


def embed_texts(texts: list[str], settings: Settings, timeout_s: int = 30) -> list[list[float]]:
    url = f"{_base_url(settings).rstrip('/')}/v1/embeddings"
    payload = {"input": texts}
    if settings.llm_embed_model_path:
        payload["model"] = settings.llm_embed_model_path
    response = requests.post(url, json=payload, timeout=timeout_s)
    response.raise_for_status()
    data = response.json()
    embeddings = []
    for item in data.get("data", []):
        embeddings.append(item.get("embedding", []))
    if len(embeddings) != len(texts):
        raise ValueError("embedding_count_mismatch")
    return embeddings


def chat_completion(
    messages: list[dict],
    settings: Settings,
    temperature: float = 0.2,
    max_tokens: int = 512,
    timeout_s: int = 60,
) -> str:
    url = f"{_base_url(settings).rstrip('/')}/v1/chat/completions"
    payload = {
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    if settings.llm_chat_model_path:
        payload["model"] = settings.llm_chat_model_path
    response = requests.post(url, json=payload, timeout=timeout_s)
    response.raise_for_status()
    data = response.json()
    choices = data.get("choices", [])
    if not choices:
        raise ValueError("missing_choices")
    message = choices[0].get("message", {})
    return message.get("content", "")

import json
import logging
import os
import time
from pathlib import Path
from typing import List

from .profiles import PROFILES
from .mock_llm import mock_generate
from .llama_http_client import post_completion, is_server_available, get_base_url
from ..config.settings import get_settings

logger = logging.getLogger(__name__)


def audit_log(profile: str, mode: str, messages: List[dict], response: str) -> None:
    log_path = Path(get_settings().log_dir) / "audit.jsonl"
    record = {
        "ts": time.time(),
        "profile": profile,
        "mode": mode,
        "messages": str(messages)[:400],
        "response": response[:400],
    }
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record) + "\n")


def generate(profile: str, messages: List[dict], temperature: float = 0.2, max_tokens: int = 256) -> str:
    settings = get_settings()
    mode = settings.llm_mode
    if profile not in PROFILES:
        raise ValueError(f"Unknown profile {profile}")

    if mode == "mock":
        response = mock_generate(profile, messages, temperature, max_tokens)
    elif mode == "local":
        base_url = get_base_url(settings)
        if not is_server_available(base_url):
            response = f"LLM backend unreachable at {base_url}"
            audit_log(profile, "local_unreachable", messages, response)
            return response
        try:
            response = post_completion(messages, temperature=temperature, max_tokens=max_tokens, base_url=base_url)
        except Exception as exc:  # noqa: BLE001
            response = f"LLM backend error at {base_url}: {exc}"
            audit_log(profile, "local_error", messages, response)
            return response
    else:
        response = mock_generate(profile, messages, temperature, max_tokens)

    audit_log(profile, mode, messages, response)
    return response

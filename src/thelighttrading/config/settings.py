from functools import lru_cache
import os
from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _default_env_path() -> str | None:
    if env_override := os.getenv("DOTENV_PATH"):
        return env_override
    if os.getenv("PYTEST_CURRENT_TEST"):
        return None
    repo_root = _repo_root()
    return str(repo_root / "runtime" / ".env")


def _default_chat_model_path() -> str | None:
    repo_root = _repo_root()
    preferred = repo_root / "runtime" / "models" / "chat" / "mistral-7b-instruct-v0.2.Q4_K_M.gguf"
    if preferred.exists():
        return str(preferred.resolve())
    chat_dir = repo_root / "runtime" / "models" / "chat"
    if chat_dir.exists():
        for candidate in sorted(chat_dir.glob("*.gguf")):
            return str(candidate.resolve())
    return None


def _default_embed_model_path() -> str | None:
    repo_root = _repo_root()
    preferred = repo_root / "runtime" / "models" / "embed" / "e5-base-v2.Q4_K_M.gguf"
    if preferred.exists():
        return str(preferred.resolve())
    embed_dir = repo_root / "runtime" / "models" / "embed"
    if embed_dir.exists():
        for candidate in sorted(embed_dir.glob("*.gguf")):
            return str(candidate.resolve())
    return None


class Settings(BaseSettings):
    app_host: str = "127.0.0.1"
    app_port: int = 8080
    gui_host: str = "127.0.0.1"
    gui_port: int = 8080
    data_dir: str = "./data"
    log_dir: str = "./logs"
    llm_mode: str = "mock"
    llm_backend: str | None = None
    llm_host: str = "127.0.0.1"
    llm_port: int = 8081
    llm_base_url: str = "http://127.0.0.1:8081"
    llm_chat_model_path: str | None = Field(default_factory=_default_chat_model_path, alias="LLM_CHAT_MODEL")
    llm_embed_model_path: str | None = Field(default_factory=_default_embed_model_path, alias="LLM_EMBED_MODEL")
    local_llm_server_url: str = "http://127.0.0.1:8081"
    local_chat_model_default: str | None = None
    local_chat_model_qwen: str | None = None
    local_chat_model_mistral: str | None = None
    local_embed_model: str | None = None
    packet_signing_private_key_base64: str | None = None
    packet_signing_public_key_base64: str | None = None
    packet_ttl_seconds: int = 120
    device_id: str = "aspire_brain_001"
    policy_text: str = "default_safety_policy_v1"
    replay_nonce_cache_size: int = 200

    model_config = SettingsConfigDict(env_file_encoding="utf-8", case_sensitive=False)

    @field_validator(
        "local_chat_model_default",
        "local_chat_model_qwen",
        "local_chat_model_mistral",
        "local_embed_model",
        "llm_chat_model_path",
        "llm_embed_model_path",
        mode="after",
    )
    def _resolve_model_paths(cls, value: str | None) -> str | None:
        if not value:
            return value
        path = Path(value)
        if not path.is_absolute():
            path = _repo_root() / path
        return str(path.resolve())

    @field_validator("llm_backend", mode="after")
    def _default_backend(cls, value: str | None, info):
        mode = info.data.get("llm_mode")
        if not value and mode == "local":
            return "llamacpp"
        return value


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    env_path = _default_env_path()
    return Settings(_env_file=env_path if env_path else None)

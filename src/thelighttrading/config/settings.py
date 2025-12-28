from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    app_host: str = "127.0.0.1"
    app_port: int = 8080
    gui_host: str = "127.0.0.1"
    gui_port: int = 8080
    data_dir: str = "./data"
    log_dir: str = "./logs"
    llm_mode: str = "mock"
    llm_base_url: str = "http://127.0.0.1:8081"
    packet_signing_private_key_base64: str | None = None
    packet_signing_public_key_base64: str | None = None
    packet_ttl_seconds: int = 120
    device_id: str = "aspire_brain_001"
    policy_text: str = "default_safety_policy_v1"
    replay_nonce_cache_size: int = 200

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", case_sensitive=False)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()

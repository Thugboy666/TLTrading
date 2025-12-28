import json
from thelighttrading.llm_router import router
from thelighttrading.config.settings import get_settings


def test_parser_profile_returns_json(monkeypatch):
    monkeypatch.setenv("LLM_MODE", "mock")
    get_settings.cache_clear()
    settings = get_settings()
    out = router.generate("parser_qwen", [{"role": "user", "content": "test"}])
    data = json.loads(out)
    assert "signals" in data
    assert isinstance(data["signals"], list)

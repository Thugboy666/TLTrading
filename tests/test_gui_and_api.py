import json
from pathlib import Path
import json
from pathlib import Path

import pytest
from thelighttrading.config.settings import get_settings
from thelighttrading.llm_router import router as llm_router
from thelighttrading.llm_router import llama_http_client
from thelighttrading.memory import node_memory


def test_gui_files_no_cdn():
    root = Path(__file__).resolve().parents[1]
    index = root / "gui" / "index.html"
    app_js = root / "gui" / "app.js"
    assert index.exists(), "index.html missing"
    assert app_js.exists(), "app.js missing"
    index_text = index.read_text(encoding="utf-8")
    app_text = app_js.read_text(encoding="utf-8")
    assert "http://" not in index_text and "https://" not in index_text
    assert "http://" not in app_text and "https://" not in app_text


def test_router_real_fallback(monkeypatch, tmp_path):
    monkeypatch.setenv("LLM_MODE", "real")
    monkeypatch.setenv("LLM_BASE_URL", "http://127.0.0.1:9999")
    monkeypatch.setenv("LOG_DIR", str(tmp_path))
    get_settings.cache_clear()

    monkeypatch.setattr(llama_http_client, "is_server_available", lambda: False)
    result = llm_router.generate("news_llama", [{"role": "user", "content": "hi"}])
    data = json.loads(result)
    assert data["ticker"] == "XYZ"

    audit_path = Path(tmp_path) / "audit.jsonl"
    assert audit_path.exists()
    last_line = audit_path.read_text(encoding="utf-8").strip().splitlines()[-1]
    record = json.loads(last_line)
    assert record["mode"] == "real_fallback"
    get_settings.cache_clear()


def test_memory_fetch_functions(monkeypatch, tmp_path):
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
    get_settings.cache_clear()

    node_memory.remember("brain", "last", {"val": 1}, 1.0)
    node_memory.remember("brain", "last", {"val": 2}, 2.0)
    node_memory.remember("brain", "other", {"val": 3}, 3.0)

    recent = node_memory.fetch_last_n("brain", 2)
    assert len(recent) == 2
    assert recent[0]["val"] in {2, 3}

    by_key = node_memory.fetch_by_key("brain", "last", 2)
    assert len(by_key) == 2
    assert {item["val"] for item in by_key} == {1, 2}
    get_settings.cache_clear()

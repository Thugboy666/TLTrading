import json

from thelighttrading.config.settings import get_settings
from thelighttrading.pipeline.runner import run_pipeline


def test_step13_pipeline_contract_mock(monkeypatch, tmp_path):
    monkeypatch.setenv("LLM_MODE", "mock")
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("LOG_DIR", str(tmp_path / "logs"))
    get_settings.cache_clear()

    result = run_pipeline("What is the market outlook?", top_k=2)

    decision = result.get("decision", {})
    assert set(decision.keys()) == {"summary", "signals", "action", "risk"}
    assert len(result.get("selected_docs", [])) <= 2

    report_path = tmp_path / "data" / "state" / "reports" / f"{result['run_id']}.json"
    assert report_path.exists()
    report = json.loads(report_path.read_text(encoding="utf-8"))
    assert report.get("decision")

    get_settings.cache_clear()

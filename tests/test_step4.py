import json
from pathlib import Path

import pytest

from thelighttrading.nodes.orchestrator import Orchestrator
from thelighttrading.nodes.registry import NodeRegistry
from thelighttrading.observability.metrics import metrics
from thelighttrading.config.settings import get_settings
from thelighttrading.memory.replay_state import save_state


@pytest.fixture(autouse=True)
def clear_settings(monkeypatch, tmp_path):
    monkeypatch.setenv("LLM_MODE", "mock")
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("LOG_DIR", str(tmp_path / "logs"))
    get_settings.cache_clear()
    save_state({})
    yield
    get_settings.cache_clear()


def test_inputs_file_txt(tmp_path):
    data_dir = tmp_path / "data"
    inputs_dir = data_dir / "inputs"
    inputs_dir.mkdir(parents=True, exist_ok=True)
    sample = inputs_dir / "headlines.txt"
    sample.write_text("Headline A\nHeadline B\n", encoding="utf-8")

    orch = Orchestrator()
    resolved = orch._resolve_headlines(None, None)
    assert resolved and resolved[0] == "Headline A"


def test_inputs_path_traversal_blocked():
    orch = Orchestrator()
    with pytest.raises(ValueError):
        orch.run_pipeline(headlines_path="../evil.txt")


def test_registry_lists_nodes():
    # ensure nodes are loaded
    _ = Orchestrator()
    registered = NodeRegistry.list_registered()
    for key in ["news", "parser", "brain", "watchdog", "packet"]:
        assert key in registered


def test_metrics_increments():
    metrics.runs_total = 0
    metrics.runs_ok = 0
    orch = Orchestrator()
    orch.run_pipeline("mock news")
    assert metrics.runs_total >= 1
    assert metrics.runs_ok >= 1

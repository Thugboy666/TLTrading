import importlib
import json

from nacl import signing
from nacl.encoding import Base64Encoder

from thelighttrading.nodes.orchestrator import Orchestrator
from thelighttrading.protocols.signing import verify_signature
from thelighttrading.config.settings import get_settings
from thelighttrading.api import routes


def test_policy_blocks_empty_entries(monkeypatch, tmp_path):
    monkeypatch.setenv("LLM_MODE", "mock")
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("LOG_DIR", str(tmp_path / "logs"))
    get_settings.cache_clear()

    from thelighttrading.llm_router import mock_llm

    original = mock_llm.mock_generate

    def fake_generate(profile: str, messages, temperature: float, max_tokens: int):
        if profile == "brain_mistral":
            return json.dumps({"entries": [], "rationale": "", "horizon_minutes": 0})
        return original(profile, messages, temperature, max_tokens)

    monkeypatch.setattr(mock_llm, "mock_generate", fake_generate)
    import thelighttrading.llm_router.router as router
    monkeypatch.setattr(router, "mock_generate", fake_generate)

    orch = Orchestrator()
    run = orch.run_pipeline("mock news")

    assert run["policy_decision"]["allow"] is False
    assert run["packet"]["intents"] == []
    assert run["status"] == "blocked"
    assert run["packet"].get("signature") is None


def test_report_signing_optional(monkeypatch, tmp_path):
    monkeypatch.setenv("LLM_MODE", "mock")
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("LOG_DIR", str(tmp_path / "logs"))
    sk = signing.SigningKey.generate()
    sk_b64 = Base64Encoder.encode(sk.encode()).decode("utf-8")
    vk_b64 = Base64Encoder.encode(sk.verify_key.encode()).decode("utf-8")
    monkeypatch.setenv("PACKET_SIGNING_PRIVATE_KEY_BASE64", sk_b64)
    monkeypatch.setenv("PACKET_SIGNING_PUBLIC_KEY_BASE64", vk_b64)
    get_settings.cache_clear()

    orch = Orchestrator()
    run = orch.run_pipeline("mock news")
    report_path = tmp_path / "data" / "state" / "reports" / f"{run['run_id']}.json"
    data = json.loads(report_path.read_text(encoding="utf-8"))
    body = {k: v for k, v in data.items() if k not in {"signature", "public_key", "report_hash"}}
    assert data.get("signature")
    assert verify_signature(body, data["signature"], data["public_key"])

    monkeypatch.delenv("PACKET_SIGNING_PRIVATE_KEY_BASE64", raising=False)
    monkeypatch.delenv("PACKET_SIGNING_PUBLIC_KEY_BASE64", raising=False)
    get_settings.cache_clear()

    orch_no_sign = Orchestrator()
    run2 = orch_no_sign.run_pipeline("mock news")
    report_path2 = tmp_path / "data" / "state" / "reports" / f"{run2['run_id']}.json"
    data2 = json.loads(report_path2.read_text(encoding="utf-8"))
    assert data2.get("signature") is None
    get_settings.cache_clear()


def test_execute_last_unsigned_rejected(monkeypatch, tmp_path):
    monkeypatch.setenv("LLM_MODE", "mock")
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("LOG_DIR", str(tmp_path / "logs"))
    monkeypatch.delenv("PACKET_SIGNING_PRIVATE_KEY_BASE64", raising=False)
    monkeypatch.delenv("PACKET_SIGNING_PUBLIC_KEY_BASE64", raising=False)
    get_settings.cache_clear()

    importlib.reload(routes)
    routes.orch.run_pipeline("mock news")

    result = routes.execute_last_packet()
    assert result["result"]["status"] == "rejected_unsigned"
    assert result["report"]["status"] == "rejected_unsigned"

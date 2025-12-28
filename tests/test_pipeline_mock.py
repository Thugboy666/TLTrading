import json
import time
from nacl.encoding import Base64Encoder
from nacl import signing
from thelighttrading.nodes.orchestrator import Orchestrator
from thelighttrading.protocols.validators import validate_signature, validate_policy_hash, validate_expiry, validate_replay
from thelighttrading.protocols.signing import compute_hash
from thelighttrading.config.settings import get_settings
from thelighttrading.memory.replay_state import save_state


def test_pipeline_mock_mode(monkeypatch, tmp_path):
    monkeypatch.setenv("LLM_MODE", "mock")
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("LOG_DIR", str(tmp_path / "logs"))
    get_settings.cache_clear()
    save_state({})

    orch = Orchestrator()
    run = orch.run_pipeline("mock news")
    packet = run["packet"]

    assert packet["policy_hash"] == compute_hash({"policy_text": get_settings().policy_text})
    assert "nonce" in packet and "sequence" in packet and "expires_at" in packet


def test_pipeline_with_signing(monkeypatch, tmp_path):
    monkeypatch.setenv("LLM_MODE", "mock")
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("LOG_DIR", str(tmp_path / "logs"))
    sk = signing.SigningKey.generate()
    sk_b64 = Base64Encoder.encode(sk.encode()).decode("utf-8")
    vk_b64 = Base64Encoder.encode(sk.verify_key.encode()).decode("utf-8")
    monkeypatch.setenv("PACKET_SIGNING_PRIVATE_KEY_BASE64", sk_b64)
    monkeypatch.setenv("PACKET_SIGNING_PUBLIC_KEY_BASE64", vk_b64)
    get_settings.cache_clear()
    save_state({})

    orch = Orchestrator()
    run = orch.run_pipeline("mock news")
    packet = run["packet"]

    body = {k: v for k, v in packet.items() if k not in {"signature", "public_key"}}
    validate_expiry(packet["expires_at"])
    validate_policy_hash(packet["policy_hash"])
    validate_signature(body, packet.get("signature"), packet.get("public_key"))
    validate_replay(packet["device_id"], packet["sequence"], packet["nonce"])

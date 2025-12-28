import json
from pathlib import Path
from typing import Dict, Any
from ..config.settings import get_settings


def _state_path() -> Path:
    settings = get_settings()
    return Path(settings.data_dir) / "state" / "replay_state.json"


def load_state() -> Dict[str, Any]:
    path = _state_path()
    if path.exists():
        with path.open("r", encoding="utf-8") as f:
            try:
                return json.load(f)
            except json.JSONDecodeError:
                return {}
    return {}


def save_state(state: Dict[str, Any]) -> None:
    path = _state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(state, f)


def check_and_update(device_id: str, sequence: int, nonce: str) -> bool:
    settings = get_settings()
    state = load_state()
    device_state = state.get(device_id, {"last_sequence": 0, "nonces": []})
    last_sequence = device_state.get("last_sequence", 0)
    nonces = device_state.get("nonces", [])

    if nonce in nonces:
        return False
    if sequence <= last_sequence:
        return False

    nonces.append(nonce)
    cache_size = settings.replay_nonce_cache_size
    if len(nonces) > cache_size:
        nonces = nonces[-cache_size:]

    state[device_id] = {"last_sequence": sequence, "nonces": nonces}
    save_state(state)
    return True

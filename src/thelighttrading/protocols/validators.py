import time
from typing import Optional
from .signing import verify_signature, compute_hash
from ..memory.replay_state import check_and_update, load_state
from ..config.settings import get_settings


class ValidationError(Exception):
    pass


def validate_expiry(expires_at: float) -> None:
    if expires_at < time.time():
        raise ValidationError("Packet expired")


def validate_policy_hash(packet_policy_hash: str) -> None:
    settings = get_settings()
    expected = compute_hash({"policy_text": settings.policy_text})
    if packet_policy_hash != expected:
        raise ValidationError("Policy hash mismatch")


def validate_signature(packet_body: dict, signature: Optional[str], public_key: Optional[str]) -> None:
    if signature is None:
        return
    if not public_key:
        raise ValidationError("Missing public key for signature")
    if not verify_signature(packet_body, signature, public_key):
        raise ValidationError("Bad signature")


def validate_replay(device_id: str, sequence: int, nonce: str, update: bool = True) -> None:
    if update:
        ok = check_and_update(device_id, sequence, nonce)
        if not ok:
            raise ValidationError("Replay detected")
        return

    state = load_state()
    device_state = state.get(device_id, {"last_sequence": 0, "nonces": []})
    last_sequence = device_state.get("last_sequence", 0)
    nonces = device_state.get("nonces", [])

    if nonce in nonces or sequence <= last_sequence:
        raise ValidationError("Replay detected")

import time

from ..protocols.schemas import ActionPacket
from ..protocols.signing import verify_signature


def simulate_execute(packet: ActionPacket) -> dict:
    now = time.time()
    body = {k: v for k, v in packet.model_dump().items() if k not in {"signature", "public_key", "hash"}}

    if packet.signature is None or not packet.public_key:
        return {"status": "rejected_unsigned"}

    if not verify_signature(body, packet.signature, packet.public_key):
        return {"status": "rejected_bad_signature"}

    if packet.expires_at < now:
        return {"status": "rejected_expired"}

    if not packet.intents:
        return {"status": "noop"}

    return {
        "status": "simulated_ok",
        "executed_intents": [intent.model_dump() for intent in packet.intents],
    }

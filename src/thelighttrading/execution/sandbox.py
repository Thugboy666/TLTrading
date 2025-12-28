import time

from ..protocols.schemas import ActionPacket


def simulate_execute(packet: ActionPacket) -> dict:
    now = time.time()
    if packet.signature is None:
        return {"status": "rejected_unsigned"}
    if packet.expires_at < now:
        return {"status": "rejected_expired"}
    if not packet.intents:
        return {"status": "noop"}
    return {
        "status": "simulated_ok",
        "executed_intents": [intent.model_dump() for intent in packet.intents],
    }

import time
import uuid
from .base import NodeResult
from .registry import register_node
from ..protocols.schemas import ActionPacket, IntentItem
from ..protocols.signing import compute_hash, sign_packet, derive_public_key
from ..protocols.validators import (
    validate_expiry,
    validate_policy_hash,
    validate_signature,
    validate_replay,
    ValidationError,
)
from ..config.settings import get_settings
from ..policy import compute_policy_hash, PolicyDecision


@register_node("packet")
class PacketNode:
    def __init__(self):
        self.id = "packet"
        self.name = "PacketNode"

    def run(
        self,
        watchdog_output: dict,
        strategy_entries: list[dict],
        policy_decision: PolicyDecision,
    ) -> NodeResult:
        ts_start = time.time()
        packet = self.build_packet(watchdog_output, strategy_entries, policy_decision)
        ts_end = time.time()
        return NodeResult(
            node_id=self.id,
            output=packet.model_dump(),
            ts_start=ts_start,
            ts_end=ts_end,
        )

    def build_packet(
        self, watchdog_output: dict, strategy_entries: list[dict], policy_decision: PolicyDecision
    ) -> ActionPacket:
        settings = get_settings()
        now = time.time()
        expires_at = now + settings.packet_ttl_seconds
        final_block = watchdog_output.get("block") or not policy_decision.allow
        intents_models = [IntentItem.model_validate(entry) for entry in strategy_entries]

        packet = ActionPacket(
            id=str(uuid.uuid4()),
            created_at=now,
            expires_at=expires_at,
            nonce=str(uuid.uuid4()),
            sequence=int(now * 1000),
            device_id=settings.device_id,
            policy_hash=compute_policy_hash(),
            intents=intents_models if not final_block else [],
        )

        packet_body = {k: v for k, v in packet.model_dump().items() if k not in {"signature", "public_key", "hash"}}
        packet_hash = compute_hash(packet_body)
        packet.hash = packet_hash

        private_key = (settings.packet_signing_private_key_base64 or "").strip() or None
        public_key = (settings.packet_signing_public_key_base64 or "").strip() or None
        if private_key and not public_key:
            public_key = derive_public_key(private_key)

        if final_block:
            packet.signature = None
            packet.public_key = public_key
            return packet

        signing_body = {k: v for k, v in packet.model_dump().items() if k not in {"signature", "public_key", "hash"}}

        if private_key:
            signature, pk_b64 = sign_packet(signing_body, private_key)
            packet.signature = signature
            packet.public_key = public_key or pk_b64
            self._validate(packet)
        else:
            packet.signature = None
            packet.public_key = public_key
        return packet

    def _validate(self, packet: ActionPacket) -> None:
        validate_expiry(packet.expires_at)
        validate_policy_hash(packet.policy_hash)
        signing_body = {k: v for k, v in packet.model_dump().items() if k not in {"signature", "public_key", "hash"}}
        validate_signature(
            signing_body,
            packet.signature,
            packet.public_key,
        )
        validate_replay(packet.device_id, packet.sequence, packet.nonce, update=False)

import json
import hashlib
from typing import Optional
from nacl import signing, exceptions
from nacl.encoding import Base64Encoder


def canonical_dumps(data: dict) -> str:
    return json.dumps(data, sort_keys=True, separators=(",", ":"))


def compute_hash(data: dict) -> str:
    canonical = canonical_dumps(data).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def sign_packet(data: dict, private_key_b64: str) -> tuple[str, str]:
    sk = signing.SigningKey(private_key_b64, encoder=Base64Encoder)
    signed = sk.sign(canonical_dumps(data).encode("utf-8"))
    signature = Base64Encoder.encode(signed.signature).decode("utf-8")
    pk_b64 = Base64Encoder.encode(sk.verify_key.encode()).decode("utf-8")
    return signature, pk_b64


def verify_signature(data: dict, signature_b64: str, public_key_b64: str) -> bool:
    vk = signing.VerifyKey(public_key_b64, encoder=Base64Encoder)
    try:
        vk.verify(canonical_dumps(data).encode("utf-8"), Base64Encoder.decode(signature_b64))
        return True
    except exceptions.BadSignatureError:
        return False


def derive_public_key(private_key_b64: str) -> Optional[str]:
    if not private_key_b64:
        return None
    sk = signing.SigningKey(private_key_b64, encoder=Base64Encoder)
    return Base64Encoder.encode(sk.verify_key.encode()).decode("utf-8")

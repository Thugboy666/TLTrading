from thelighttrading.protocols.signing import canonical_dumps, compute_hash, sign_packet, verify_signature
import json
from nacl.encoding import Base64Encoder
from nacl import signing


def test_sign_and_verify_roundtrip():
    payload = {"a": 1, "b": 2}
    data = json.loads(canonical_dumps(payload))
    sk = signing.SigningKey.generate()
    sk_b64 = Base64Encoder.encode(sk.encode()).decode("utf-8")
    vk_b64 = Base64Encoder.encode(sk.verify_key.encode()).decode("utf-8")

    signature, derived_pk = sign_packet(data, sk_b64)
    assert derived_pk == vk_b64
    assert verify_signature(data, signature, vk_b64)
    assert compute_hash(data) == compute_hash(payload)

import time
import json
from thelighttrading.protocols.validators import validate_replay, ValidationError
from thelighttrading.memory.replay_state import load_state, save_state
from thelighttrading.config.settings import get_settings


def setup_function(_):
    # reset state
    save_state({})


def test_replay_nonce_and_sequence():
    device_id = "dev1"
    nonce = "abc"
    sequence = int(time.time())

    validate_replay(device_id, sequence, nonce)  # first passes

    # same nonce should fail
    try:
        validate_replay(device_id, sequence + 1, nonce)
        assert False, "Expected replay detection"
    except ValidationError:
        pass

    # lower sequence should fail
    nonce2 = "def"
    try:
        validate_replay(device_id, sequence - 1, nonce2)
        assert False, "Expected sequence replay detection"
    except ValidationError:
        pass

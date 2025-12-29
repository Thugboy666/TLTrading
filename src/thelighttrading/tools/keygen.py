"""Signing key utilities."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Tuple
from nacl import signing
from nacl.encoding import Base64Encoder

PRIVATE_ENV = "PACKET_SIGNING_PRIVATE_KEY_BASE64"
PUBLIC_ENV = "PACKET_SIGNING_PUBLIC_KEY_BASE64"


def generate_keypair_base64() -> Tuple[str, str]:
    sk = signing.SigningKey.generate()
    pk = sk.verify_key
    private_b64 = Base64Encoder.encode(sk.encode()).decode("utf-8")
    public_b64 = Base64Encoder.encode(pk.encode()).decode("utf-8")
    return private_b64, public_b64


def write_env_file(path: str | Path, private_b64: str, public_b64: str, overwrite: bool = False) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)

    lines: list[str] = []
    if target.exists():
        lines = target.read_text(encoding="utf-8").splitlines()

    replacements = {
        PRIVATE_ENV: private_b64,
        PUBLIC_ENV: public_b64,
    }

    new_lines: list[str] = []
    seen: set[str] = set()
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in line:
            new_lines.append(line)
            continue
        key, _ = line.split("=", 1)
        key = key.strip()
        if key in replacements:
            if overwrite or key not in seen:
                new_lines.append(f"{key}={replacements[key]}")
            else:
                new_lines.append(line)
            seen.add(key)
        else:
            new_lines.append(line)

    for key, value in replacements.items():
        if key not in seen:
            new_lines.append(f"{key}={value}")

    target.write_text("\n".join(new_lines) + ("\n" if new_lines else ""), encoding="utf-8")
    return target


def _default_env_path() -> Path:
    return Path(__file__).resolve().parents[3] / "runtime" / ".env"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate packet signing keys and write them to an env file.")
    parser.add_argument("--out", default=str(_default_env_path()), help="Path to the env file to update.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing key values if they exist.")
    args = parser.parse_args(argv)

    private_b64, public_b64 = generate_keypair_base64()
    env_path = write_env_file(args.out, private_b64, public_b64, overwrite=args.overwrite)

    print(f"Wrote signing keys to {env_path.resolve()} (public key stored).")
    print("Private key content is not displayed; keep the env file secure.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

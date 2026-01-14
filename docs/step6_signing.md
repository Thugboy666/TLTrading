# Step 6: Packet signing and env configuration

This project expects signing keys to live in `runtime/.env` (or another location specified via `DOTENV_PATH`). The helpers below generate keys, write them to the env file, and demonstrate the expected API behavior.

## Generate signing keys

1. Ensure the virtual environment exists (`scripts/setup_windows.ps1`).
2. Run the key generator (creates `runtime/.env` if needed):
   ```powershell
   scripts/keygen.ps1
   ```
3. The script writes `PACKET_SIGNING_PRIVATE_KEY_BASE64` and `PACKET_SIGNING_PUBLIC_KEY_BASE64` to `runtime/.env` and keeps the private key out of the console output.

## Run the API with runtime env

```powershell
scripts/run_api.ps1
```

The script exports `DOTENV_PATH` to `runtime/.env` before starting Uvicorn, so settings and signing keys load automatically.

## Verify signing behavior

1. Hit the latest packet endpoint:
   ```powershell
   Invoke-WebRequest -Uri "http://127.0.0.1:8080/packet/last"
   ```
   * When signing keys exist, packets include `signature` and `public_key` values.
   * Without keys, both fields are `null`.
2. Execute the last packet:
   ```powershell
   Invoke-WebRequest -Method Post -Uri "http://127.0.0.1:8080/execute/last"
   ```
   * Signed packets proceed to execution.
   * Missing signatures return `status: "rejected_unsigned"`.
   * Bad signatures return `status: "rejected_bad_signature"` before any execution attempts.

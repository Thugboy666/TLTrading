import json
import time
from pathlib import Path
from .schemas import ExecutionReport
from .signing import compute_hash, sign_packet, derive_public_key
from ..config.settings import get_settings


def _report_body(report: ExecutionReport) -> dict:
    return {k: v for k, v in report.model_dump().items() if k not in {"signature", "public_key", "report_hash"}}


def build_execution_report(run_record: dict, status_override: str | None = None) -> ExecutionReport:
    packet = run_record.get("packet", {}) if run_record else {}
    packet_id = packet.get("id", "")
    packet_body = {k: v for k, v in packet.items() if k not in {"signature", "public_key", "hash"}}
    packet_hash = packet.get("hash") or (compute_hash(packet_body) if packet else None)
    status = status_override or run_record.get("status", "unknown")
    report = ExecutionReport(
        run_id=run_record.get("run_id", ""),
        packet_id=packet_id,
        created_at=time.time(),
        status=status,
        node_statuses=run_record.get("nodes", []),
        packet_hash=packet_hash,
    )

    # Always pull signing material from the current settings to avoid
    # reusing stale environment configuration across runs.
    settings = get_settings()
    body = _report_body(report)
    report.report_hash = compute_hash(body)

    private_key = settings.packet_signing_private_key_base64 or None
    public_key = (
        settings.packet_signing_public_key_base64
        if not private_key
        else settings.packet_signing_public_key_base64 or derive_public_key(private_key)
    )

    if private_key:
        signature, pk_b64 = sign_packet(body, private_key)
        report.signature = signature
        report.public_key = public_key or pk_b64
    else:
        report.signature = None
        report.public_key = public_key
    return report


def persist_report(run_id: str, report: ExecutionReport) -> Path:
    reports_dir = Path(get_settings().data_dir) / "state" / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)
    report_path = reports_dir / f"{run_id}.json"
    with report_path.open("w", encoding="utf-8") as f:
        json.dump(report.model_dump(), f, indent=2)
    return report_path

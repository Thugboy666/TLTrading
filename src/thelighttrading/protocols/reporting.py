import json
import time
from pathlib import Path
from .schemas import ExecutionReport
from ..config.settings import get_settings


def build_execution_report(run_record: dict) -> ExecutionReport:
    packet = run_record.get("packet", {}) if run_record else {}
    packet_id = packet.get("id", "")
    status = "ok" if packet else "unknown"
    details = {"nodes": run_record.get("nodes", []), "packet": packet}
    report = ExecutionReport(
        packet_id=packet_id,
        executed_at=time.time(),
        status=status,
        details=details,
    )
    return report


def persist_report(run_id: str, report: ExecutionReport) -> Path:
    reports_dir = Path(get_settings().data_dir) / "state" / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)
    report_path = reports_dir / f"{run_id}.json"
    with report_path.open("w", encoding="utf-8") as f:
        json.dump(report.model_dump(), f, indent=2)
    return report_path

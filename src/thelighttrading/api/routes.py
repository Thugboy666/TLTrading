import json
import time
from pathlib import Path
from fastapi import APIRouter, HTTPException
from ..nodes.orchestrator import Orchestrator
from ..config.settings import get_settings
from ..execution import simulate_execute
from ..llm_router.profiles import PROFILES
from ..memory.node_memory import fetch_last_n, fetch_by_key
from ..protocols.reporting import build_execution_report, persist_report
from ..protocols.schemas import ActionPacket

router = APIRouter()
orch = Orchestrator()


@router.get("/health")
def health():
    return {"ok": True}


@router.get("/status")
def status():
    settings = get_settings()
    last_run_path = Path(settings.data_dir) / "state" / "last_run.txt"
    last_run_id = last_run_path.read_text().strip() if last_run_path.exists() else None
    return {
        "mode": settings.llm_mode,
        "profiles": list(PROFILES.keys()),
        "last_run_id": last_run_id,
    }


@router.post("/pipeline/run")
def run_pipeline(payload: dict | None = None):
    headlines = None
    if payload and "headlines" in payload:
        headlines = payload["headlines"]
    result = orch.run_pipeline(headlines)
    return result


@router.get("/pipeline/run/{run_id}")
def get_run(run_id: str):
    return _load_run(run_id)


@router.get("/report/run/{run_id}")
def get_report(run_id: str):
    return _load_or_build_report(run_id)


@router.get("/report/last")
def get_last_report():
    run_id = _get_last_run_id()
    if not run_id:
        raise HTTPException(status_code=404, detail="no runs yet")
    return _load_or_build_report(run_id)


@router.get("/packet/last")
def get_last_packet():
    run_id = _get_last_run_id()
    if not run_id:
        raise HTTPException(status_code=404, detail="no packets")
    run_record = _load_run(run_id)
    return run_record.get("packet")


@router.post("/execute/last")
def execute_last_packet():
    run_id = _get_last_run_id()
    if not run_id:
        raise HTTPException(status_code=404, detail="no runs to execute")
    run_record = _load_run(run_id)
    packet_data = run_record.get("packet")
    if not packet_data:
        raise HTTPException(status_code=404, detail="no packet available")

    packet = ActionPacket.model_validate(packet_data)
    result = simulate_execute(packet)

    _append_audit({"type": "execution", "run_id": run_id, "packet_id": packet.id, "status": result.get("status"), "ts": time.time()})

    report = build_execution_report(run_record, status_override=result.get("status"))
    persist_report(run_id, report)

    return {"run_id": run_id, "result": result, "report": report.model_dump()}


@router.get("/memory/node/{node_id}")
def get_memory(node_id: str, n: int = 10):
    return fetch_last_n(node_id, n)


@router.get("/memory/node/{node_id}/key/{key}")
def get_memory_by_key(node_id: str, key: str, n: int = 10):
    return fetch_by_key(node_id, key, n)


def _get_last_run_id() -> str | None:
    settings = get_settings()
    last_run_path = Path(settings.data_dir) / "state" / "last_run.txt"
    return last_run_path.read_text().strip() if last_run_path.exists() else None


def _load_run(run_id: str) -> dict:
    run_path = Path(get_settings().data_dir) / "state" / "runs" / f"{run_id}.json"
    if not run_path.exists():
        raise HTTPException(status_code=404, detail="run not found")
    with run_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _load_or_build_report(run_id: str) -> dict:
    report_path = Path(get_settings().data_dir) / "state" / "reports" / f"{run_id}.json"
    if report_path.exists():
        with report_path.open("r", encoding="utf-8") as f:
            return json.load(f)

    run_record = _load_run(run_id)
    report = build_execution_report(run_record)
    persist_report(run_id, report)
    return report.model_dump()


def _append_audit(record: dict) -> None:
    log_path = Path(get_settings().log_dir) / "audit.jsonl"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record) + "\n")

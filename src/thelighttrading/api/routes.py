import json
import time
from pathlib import Path
from fastapi import APIRouter, HTTPException
from ..nodes.orchestrator import Orchestrator
from ..pipeline.runner import run_pipeline as run_rag_pipeline
from ..config.settings import get_settings
from ..execution import simulate_execute
from ..protocols.signing import verify_signature
from ..llm_router.profiles import PROFILES
from ..llm_router import llama_http_client
from ..memory.node_memory import fetch_last_n, fetch_by_key
from ..observability.metrics import metrics
from ..protocols.reporting import build_execution_report, persist_report
from ..protocols.schemas import ActionPacket

router = APIRouter()
orch = Orchestrator()


@router.get("/health")
def health():
    settings = get_settings()
    repo_root = Path(__file__).resolve().parents[3]
    state_dir = repo_root / "runtime" / "state"
    status_path = state_dir / "api.status.json"
    status_content = _load_json(status_path)

    pid = None
    uptime_seconds = 0
    ok = False

    if isinstance(status_content, dict):
        status_pid = status_content.get("pid")
        started_at = status_content.get("started_at")
        status_flag = status_content.get("status")
        if isinstance(status_pid, int) and isinstance(started_at, (int, float)) and status_flag == "running":
            pid = status_pid
            uptime_seconds = max(0, int(time.time() - started_at))
            ok = True

    last_run_path = state_dir / "last_run.json"
    last_run = _load_json(last_run_path)

    response = {
        "ok": ok,
        "pid": pid,
        "uptime_seconds": uptime_seconds,
        "llm_mode": settings.llm_mode,
    }

    if last_run is not None:
        response["last_run"] = last_run

    return response


@router.get("/llm/health")
def llm_health():
    settings = get_settings()
    base_url = llama_http_client.get_base_url(settings) if settings.llm_mode != "mock" else None
    response = {
        "ok": True,
        "mode": settings.llm_mode,
        "backend": settings.llm_backend,
        "base_url": base_url,
        "chat_model": settings.llm_chat_model_path,
        "embed_model": settings.llm_embed_model_path,
    }

    if settings.llm_mode == "mock":
        return response

    if not base_url:
        response["ok"] = False
        response["reason"] = "missing base URL"
        return response

    try:
        available = llama_http_client.is_server_available(base_url)
        response["ok"] = available
        if not available:
            response["reason"] = f"unreachable at {base_url}"
    except Exception as exc:  # noqa: BLE001
        response["ok"] = False
        response["reason"] = str(exc)

    return response


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


@router.get("/metrics")
def get_metrics():
    return metrics.snapshot()


@router.get("/inputs/status")
def get_inputs_status():
    inputs_dir = Path(get_settings().data_dir) / "inputs"
    files = []
    if inputs_dir.exists():
        for item in inputs_dir.iterdir():
            if item.is_file():
                files.append(item.name)
    return {"files": sorted(files)}


@router.post("/pipeline/run")
def run_pipeline(payload: dict | None = None):
    if payload and ("query" in payload or "top_k" in payload):
        query = payload.get("query", "") if payload else ""
        top_k = payload.get("top_k", 5) if payload else 5
        return run_rag_pipeline(query, top_k=top_k)

    headlines = None
    headlines_path = None
    if payload and "headlines" in payload:
        headlines = payload["headlines"]
    if payload and "headlines_path" in payload:
        headlines_path = payload["headlines_path"]
    try:
        result = orch.run_pipeline(headlines, headlines_path=headlines_path)
    except ValueError as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=str(exc))
    return result


@router.get("/pipeline/last")
def get_pipeline_last():
    state_dir = Path(get_settings().data_dir) / "state"
    last_path = state_dir / "pipeline_last.json"
    if not last_path.exists():
        raise HTTPException(status_code=404, detail="no pipeline runs yet")
    with last_path.open("r", encoding="utf-8") as f:
        return json.load(f)


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

    signing_body = {k: v for k, v in packet.model_dump().items() if k not in {"signature", "public_key", "hash"}}

    if packet.signature is None or not packet.public_key:
        result = {"status": "rejected_unsigned"}
    elif not verify_signature(signing_body, packet.signature, packet.public_key):
        result = {"status": "rejected_bad_signature"}
    else:
        result = simulate_execute(packet)
    metrics.executions_total += 1

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


def _load_json(path: Path):
    if not path.exists():
        return None
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return None


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
    sanitized = {k: v for k, v in record.items() if not k.lower().startswith("packet_signing_private")}
    with log_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(sanitized)[:400] + "\n")

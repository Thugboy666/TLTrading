import json
from pathlib import Path
from fastapi import APIRouter, HTTPException
from ..nodes.orchestrator import Orchestrator
from ..config.settings import get_settings
from ..llm_router.profiles import PROFILES

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
    run_path = Path(get_settings().data_dir) / "state" / "runs" / f"{run_id}.json"
    if not run_path.exists():
        raise HTTPException(status_code=404, detail="run not found")
    with run_path.open("r", encoding="utf-8") as f:
        return json.load(f)


@router.get("/packet/last")
def get_last_packet():
    state_dir = Path(get_settings().data_dir) / "state" / "runs"
    if not state_dir.exists():
        raise HTTPException(status_code=404, detail="no packets")
    runs = sorted(state_dir.glob("*.json"))
    if not runs:
        raise HTTPException(status_code=404, detail="no packets")
    with runs[-1].open("r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("packet")

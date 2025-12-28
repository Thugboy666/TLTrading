import json
from pathlib import Path
import uvicorn
import typer
from ..api.server import app as api_app
from ..nodes.orchestrator import Orchestrator
from ..execution import simulate_execute
from ..config.settings import get_settings
from ..protocols.schemas import ActionPacket
from ..protocols.reporting import build_execution_report, persist_report

app = typer.Typer()


@app.command("run-api")
def run_api():
    settings = get_settings()
    uvicorn.run(api_app, host=settings.app_host, port=settings.app_port)


@app.command("run-pipeline")
def run_pipeline(headlines: str = "Mock headlines"):
    orch = Orchestrator()
    result = orch.run_pipeline(headlines)
    typer.echo(json.dumps(result, indent=2))


@app.command("show-last-packet")
def show_last_packet():
    settings = get_settings()
    state_dir = Path(settings.data_dir) / "state" / "runs"
    runs = sorted(state_dir.glob("*.json")) if state_dir.exists() else []
    if not runs:
        typer.echo("No packets yet")
        raise typer.Exit(code=1)
    with runs[-1].open("r", encoding="utf-8") as f:
        data = json.load(f)
    typer.echo(json.dumps(data.get("packet"), indent=2))


@app.command("execute-last")
def execute_last():
    settings = get_settings()
    state_dir = Path(settings.data_dir) / "state" / "runs"
    runs = sorted(state_dir.glob("*.json")) if state_dir.exists() else []
    if not runs:
        typer.echo("No runs yet")
        raise typer.Exit(code=1)
    run_path = runs[-1]
    with run_path.open("r", encoding="utf-8") as f:
        run_record = json.load(f)
    packet_data = run_record.get("packet")
    if not packet_data:
        typer.echo("No packet to execute")
        raise typer.Exit(code=1)

    packet = ActionPacket.model_validate(packet_data)
    result = simulate_execute(packet)
    report = build_execution_report(run_record, status_override=result.get("status"))
    persist_report(run_record.get("run_id", run_path.stem), report)

    typer.echo(json.dumps({"result": result, "report": report.model_dump()}, indent=2))

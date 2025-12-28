import json
from pathlib import Path
import uvicorn
import typer
from ..api.server import app as api_app
from ..nodes.orchestrator import Orchestrator
from ..config.settings import get_settings

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

import json
from pathlib import Path
import uvicorn
import typer
from nacl import signing
from nacl.encoding import Base64Encoder
from ..api.server import app as api_app
from ..pipeline.runner import run_pipeline as run_rag_pipeline
from ..execution import simulate_execute
from ..config.settings import get_settings
from ..protocols.schemas import ActionPacket, ExecutionReport
from ..protocols.reporting import build_execution_report, persist_report
from ..protocols.validators import validate_signature, validate_policy_hash, validate_expiry
from ..protocols.signing import compute_hash
from ..scheduler.job_runner import run_loop

app = typer.Typer()


@app.command("run-api")
def run_api():
    settings = get_settings()
    uvicorn.run(api_app, host=settings.app_host, port=settings.app_port)


@app.command("run-pipeline")
def run_pipeline(query: str = typer.Option("Mock query", "--query"), top_k: int = typer.Option(5, "--top-k")):
    result = run_rag_pipeline(query, top_k=top_k)
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


@app.command("gen-keys")
def gen_keys(out: Path | None = typer.Option(None, "--out")):
    sk = signing.SigningKey.generate()
    pk = sk.verify_key
    sk_b64 = Base64Encoder.encode(sk.encode()).decode("utf-8")
    pk_b64 = Base64Encoder.encode(pk.encode()).decode("utf-8")
    typer.echo(json.dumps({"private_key": sk_b64, "public_key": pk_b64}, indent=2))
    if out:
        env_content = f"PACKET_SIGNING_PRIVATE_KEY_BASE64={sk_b64}\nPACKET_SIGNING_PUBLIC_KEY_BASE64={pk_b64}\n"
        out.write_text(env_content, encoding="utf-8")
        typer.echo(f"Written to {out}")


@app.command("verify-packet")
def verify_packet(path: Path = typer.Option(..., exists=True, readable=True)):
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    packet = ActionPacket.model_validate(data)
    body = {k: v for k, v in packet.model_dump().items() if k not in {"signature", "public_key", "hash"}}
    validate_expiry(packet.expires_at)
    validate_policy_hash(packet.policy_hash)
    if packet.signature and packet.public_key:
        validate_signature(body, packet.signature, packet.public_key)
    typer.echo("packet: ok")


@app.command("verify-report")
def verify_report(path: Path = typer.Option(..., exists=True, readable=True)):
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    report = ExecutionReport.model_validate(data)
    body = {k: v for k, v in report.model_dump().items() if k not in {"signature", "public_key", "report_hash"}}
    hash_value = compute_hash(body)
    if report.report_hash and report.report_hash != hash_value:
        raise typer.Exit(code=1)
    typer.echo("report: ok")


@app.command("run-daemon")
def run_daemon(interval: int = typer.Option(60, min=1), once: bool = False):
    run_loop(interval_seconds=interval, once=once)

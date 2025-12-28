import logging.config
import yaml
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from pathlib import Path
from .routes import router
from ..config.settings import get_settings

logging_config_path = Path(__file__).resolve().parents[2] / "config" / "logging.yaml"
if logging_config_path.exists():
    with logging_config_path.open("r", encoding="utf-8") as f:
        config = yaml.safe_load(f)
        logging.config.dictConfig(config)

app = FastAPI(title="TheLightTrading API")
app.include_router(router)

settings = get_settings()
gui_path = Path(__file__).resolve().parents[3] / "gui"
app.mount("/", StaticFiles(directory=gui_path, html=True), name="gui")

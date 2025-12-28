import json
import sqlite3
from pathlib import Path
from ..config.settings import get_settings

DB_NAME = "thelighttrading.db"


def _get_conn():
    data_dir = Path(get_settings().data_dir) / "memory"
    data_dir.mkdir(parents=True, exist_ok=True)
    db_path = data_dir / DB_NAME
    conn = sqlite3.connect(db_path)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS node_memory (
            node_id TEXT,
            ts REAL,
            key TEXT,
            value_json TEXT
        )
        """
    )
    return conn


def remember(node_id: str, key: str, value: dict, ts: float) -> None:
    conn = _get_conn()
    with conn:
        conn.execute(
            "INSERT INTO node_memory (node_id, ts, key, value_json) VALUES (?, ?, ?, ?)",
            (node_id, ts, key, json.dumps(value)),
        )
    conn.close()


def fetch_latest(node_id: str) -> dict | None:
    conn = _get_conn()
    cur = conn.execute(
        "SELECT value_json FROM node_memory WHERE node_id=? ORDER BY ts DESC LIMIT 1",
        (node_id,),
    )
    row = cur.fetchone()
    conn.close()
    if not row:
        return None
    return json.loads(row[0])


def fetch_last_n(node_id: str, n: int) -> list[dict]:
    conn = _get_conn()
    cur = conn.execute(
        "SELECT value_json FROM node_memory WHERE node_id=? ORDER BY ts DESC LIMIT ?",
        (node_id, n),
    )
    rows = cur.fetchall()
    conn.close()
    return [json.loads(r[0]) for r in rows]


def fetch_by_key(node_id: str, key: str, n: int = 10) -> list[dict]:
    conn = _get_conn()
    cur = conn.execute(
        "SELECT value_json FROM node_memory WHERE node_id=? AND key=? ORDER BY ts DESC LIMIT ?",
        (node_id, key, n),
    )
    rows = cur.fetchall()
    conn.close()
    return [json.loads(r[0]) for r in rows]

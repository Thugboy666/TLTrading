import hashlib
import json
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
import shutil

from ..config.settings import get_settings
from ..policy import load_policy_text
from .local_llm_client import chat_completion, embed_texts
from .retrieval import rank_documents


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _new_run_id() -> str:
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    short_uuid = uuid.uuid4().hex[:8]
    return f"run_{ts}_{short_uuid}"


def _deterministic_embedding(text: str, dims: int = 8) -> list[float]:
    digest = hashlib.sha256(text.encode("utf-8")).digest()
    values = []
    for idx in range(dims):
        start = idx * 2
        chunk = digest[start : start + 2]
        val = int.from_bytes(chunk, "big")
        values.append((val / 65535.0) * 2.0 - 1.0)
    return values


def _hash_content(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _load_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return None


def _seed_news_samples(news_dir: Path) -> None:
    if any(news_dir.glob("*.json")):
        return
    samples_dir = _repo_root() / "runtime" / "state" / "news_samples"
    if not samples_dir.exists():
        return
    news_dir.mkdir(parents=True, exist_ok=True)
    for sample in samples_dir.glob("*.json"):
        dest = news_dir / sample.name
        if not dest.exists():
            shutil.copy2(sample, dest)


def _load_documents(news_dir: Path) -> list[dict[str, Any]]:
    docs = []
    for path in sorted(news_dir.glob("*.json")):
        data = _load_json(path)
        if not data:
            continue
        doc_id = data.get("id") or path.stem
        title = data.get("title") or ""
        content = data.get("content") or ""
        source = data.get("source") or ""
        created_at = data.get("created_at") or None
        docs.append(
            {
                "id": doc_id,
                "title": title,
                "content": content,
                "source": source,
                "created_at": created_at,
                "path": str(path),
            }
        )
    return docs


def _ensure_embeddings(docs: list[dict[str, Any]], index_dir: Path, mode: str) -> list[dict[str, Any]]:
    settings = get_settings()
    index_dir.mkdir(parents=True, exist_ok=True)
    embeddings_map: dict[str, list[float]] = {}

    texts_to_embed = []
    doc_ids_to_embed = []

    for doc in docs:
        doc_id = doc["id"]
        content = f"{doc.get('title', '')}\n{doc.get('content', '')}".strip()
        content_hash = _hash_content(content)
        index_path = index_dir / f"{doc_id}.json"
        index_data = _load_json(index_path)
        if index_data and index_data.get("content_hash") == content_hash:
            embedding = index_data.get("embedding")
            if embedding:
                embeddings_map[doc_id] = embedding
                continue
        if mode == "mock":
            embeddings_map[doc_id] = _deterministic_embedding(content)
        else:
            texts_to_embed.append(content)
            doc_ids_to_embed.append(doc_id)
        doc["content_hash"] = content_hash

    if texts_to_embed:
        try:
            vectors = embed_texts(texts_to_embed, settings)
            for doc_id, vector in zip(doc_ids_to_embed, vectors):
                embeddings_map[doc_id] = vector
        except Exception:  # noqa: BLE001
            for doc_id, content in zip(doc_ids_to_embed, texts_to_embed):
                embeddings_map[doc_id] = _deterministic_embedding(content)

    for doc in docs:
        doc_id = doc["id"]
        embedding = embeddings_map.get(doc_id)
        if not embedding:
            continue
        doc["embedding"] = embedding
        index_path = index_dir / f"{doc_id}.json"
        index_payload = {
            "id": doc_id,
            "content_hash": doc.get("content_hash") or _hash_content(doc.get("content", "")),
            "embedding": embedding,
            "metadata": {
                "title": doc.get("title"),
                "source": doc.get("source"),
                "created_at": doc.get("created_at"),
            },
        }
        with index_path.open("w", encoding="utf-8") as f:
            json.dump(index_payload, f, indent=2)

    return docs


def _build_prompt(query: str, snippets: list[dict[str, Any]], policy_text: str) -> list[dict[str, str]]:
    system = (
        "You are a trading decision engine. Reply ONLY with JSON that matches this schema: "
        "{summary: string, signals: [{name: string, direction: bullish|bearish|neutral, confidence: 0-1}], "
        "action: {type: HOLD|SIMULATE|EXECUTE, reason: string}, risk: {level: low|medium|high, notes: string}}. "
        "Do not include markdown or extra keys."
    )
    user_payload = {
        "query": query,
        "documents": snippets,
        "policy": policy_text,
    }
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": json.dumps(user_payload)},
    ]


def _parse_decision(raw_text: str) -> dict[str, Any] | None:
    try:
        data = json.loads(raw_text)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    required = {"summary", "signals", "action", "risk"}
    if not required.issubset(data.keys()):
        return None
    return data


def _fallback_decision(reason: str) -> dict[str, Any]:
    return {
        "summary": "Pipeline decision fallback",
        "signals": [],
        "action": {"type": "HOLD", "reason": reason},
        "risk": {"level": "medium", "notes": reason},
    }


def _enforce_signing_policy(decision: dict[str, Any]) -> dict[str, Any]:
    settings = get_settings()
    private_key = (settings.packet_signing_private_key_base64 or "").strip()
    public_key = (settings.packet_signing_public_key_base64 or "").strip()
    allow_execute = bool(private_key and public_key)
    action = decision.get("action", {})
    if action.get("type") == "EXECUTE" and not allow_execute:
        action = {"type": "HOLD", "reason": "unsigned_packets_not_allowed"}
        decision = {**decision, "action": action}
    return decision


def _log_pipeline(log_path: Path, message: str) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).isoformat()
    with log_path.open("a", encoding="utf-8") as f:
        f.write(f"[{timestamp}] {message}\n")


def run_pipeline(query: str, top_k: int = 5) -> dict[str, Any]:
    settings = get_settings()
    mode = settings.llm_mode
    data_root = Path(settings.data_dir)
    log_root = Path(settings.log_dir)
    state_dir = data_root / "state"
    news_dir = state_dir / "news"
    index_dir = state_dir / "index"
    reports_dir = state_dir / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)

    _seed_news_samples(news_dir)

    docs = _load_documents(news_dir)
    docs = _ensure_embeddings(docs, index_dir, mode)

    query_text = query or ""
    if mode == "mock":
        query_embedding = _deterministic_embedding(query_text)
    else:
        try:
            query_embedding = embed_texts([query_text], settings)[0]
        except Exception:  # noqa: BLE001
            query_embedding = _deterministic_embedding(query_text)

    ranked = rank_documents(query_embedding, docs, top_k=top_k)
    snippets = []
    for doc in ranked:
        content = doc.get("content", "")
        snippet = content[:280]
        snippets.append(
            {
                "id": doc.get("id"),
                "title": doc.get("title"),
                "source": doc.get("source"),
                "created_at": doc.get("created_at"),
                "snippet": snippet,
                "score": doc.get("score"),
            }
        )

    policy_text = load_policy_text()
    decision = None
    if mode == "mock":
        decision = {
            "summary": f"Mock decision for query: {query_text}",
            "signals": [
                {"name": "market_sentiment", "direction": "neutral", "confidence": 0.5},
            ],
            "action": {"type": "HOLD", "reason": "mock_mode"},
            "risk": {"level": "low", "notes": "mock_mode"},
        }
    else:
        messages = _build_prompt(query_text, snippets, policy_text)
        try:
            response = chat_completion(messages, settings)
        except Exception:  # noqa: BLE001
            response = ""
        decision = _parse_decision(response) or _fallback_decision("invalid_model_output")

    decision = _enforce_signing_policy(decision)

    run_id = _new_run_id()
    created_at = time.time()
    run_record = {
        "run_id": run_id,
        "created_at": created_at,
        "mode": mode,
        "query": query_text,
        "top_k": top_k,
        "selected_docs": snippets,
        "decision": decision,
    }

    report_path = reports_dir / f"{run_id}.json"
    with report_path.open("w", encoding="utf-8") as f:
        json.dump(run_record, f, indent=2)

    last_path = state_dir / "pipeline_last.json"
    with last_path.open("w", encoding="utf-8") as f:
        json.dump(run_record, f, indent=2)

    _log_pipeline(log_root / "pipeline.log", f"run_id={run_id} action={decision.get('action', {}).get('type')} query={query_text}")

    return run_record

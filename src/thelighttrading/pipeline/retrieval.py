import math
from typing import Iterable, Sequence


Vector = Sequence[float]


def cosine_similarity(vec_a: Vector, vec_b: Vector) -> float:
    if not vec_a or not vec_b:
        return 0.0
    if len(vec_a) != len(vec_b):
        return 0.0
    dot = 0.0
    norm_a = 0.0
    norm_b = 0.0
    for a, b in zip(vec_a, vec_b):
        dot += a * b
        norm_a += a * a
        norm_b += b * b
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    return dot / (math.sqrt(norm_a) * math.sqrt(norm_b))


def rank_documents(query_embedding: Vector, documents: Iterable[dict], top_k: int = 5) -> list[dict]:
    scored = []
    for doc in documents:
        embedding = doc.get("embedding")
        if not embedding:
            continue
        score = cosine_similarity(query_embedding, embedding)
        scored.append({**doc, "score": score})
    scored.sort(key=lambda item: item.get("score", 0.0), reverse=True)
    return scored[: max(top_k, 0)]

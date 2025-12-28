from __future__ import annotations

import json
from pathlib import Path
from typing import List


def read_headlines_from_file(path: str | Path) -> List[str]:
    file_path = Path(path)
    if not file_path.exists():
        return []

    content: List[str] = []
    if file_path.suffix.lower() == ".json":
        with file_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        headlines = data.get("headlines", []) if isinstance(data, dict) else []
        content = [str(h) for h in headlines]
    else:
        with file_path.open("r", encoding="utf-8") as f:
            content = [line.strip() for line in f.readlines()]

    sanitized = []
    for item in content:
        text = item.strip()
        if text:
            sanitized.append(text)
        if len(sanitized) >= 50:
            break
    return sanitized

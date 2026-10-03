"""Reads and writes the list of customers as one JSON file."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path

from customerdb.models import Customer


class JsonStore:
    def __init__(self, path: str | os.PathLike[str]) -> None:
        self.path = Path(path)

    def load(self) -> list[Customer]:
        if not self.path.exists():
            return []
        data = json.loads(self.path.read_text(encoding="utf-8"))
        return [Customer.from_dict(row) for row in data["customers"]]

    def save(self, customers: list[Customer]) -> None:
        data = {"customers": [c.to_dict() for c in customers]}
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # write to a temp file in the same directory, then rename: never a half-written db
        fd, tmp = tempfile.mkstemp(dir=self.path.parent, suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp, self.path)

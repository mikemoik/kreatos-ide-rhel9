"""The Customer record and its validation."""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass
from typing import Any

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+$")


class ValidationError(ValueError):
    """A customer field has an invalid value."""


@dataclass
class Customer:
    id: int
    name: str
    email: str
    city: str = ""

    def validate(self) -> None:
        if not self.name.strip():
            raise ValidationError("name must not be empty")
        if not EMAIL_RE.match(self.email):
            raise ValidationError(f"invalid email: {self.email!r}")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, row: dict[str, Any]) -> Customer:
        return cls(
            id=int(row["id"]), name=row["name"], email=row["email"], city=row.get("city", "")
        )

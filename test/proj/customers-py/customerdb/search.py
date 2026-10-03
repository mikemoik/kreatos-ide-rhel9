"""Matching customers against a search text."""

from __future__ import annotations

from customerdb.models import Customer

SEARCH_FIELDS = ("name", "email", "city")


def normalize(text: str) -> str:
    return " ".join(text.lower().split())


def matches(customer: Customer, text: str) -> bool:
    """Case-insensitive substring match on any of SEARCH_FIELDS."""
    needle = normalize(text)
    return any(needle in normalize(getattr(customer, field)) for field in SEARCH_FIELDS)

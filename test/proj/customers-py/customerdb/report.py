"""Summaries over all customers."""

from __future__ import annotations

from collections import Counter

from customerdb.models import Customer


def customers_per_city(customers: list[Customer]) -> dict[str, int]:
    counts = Counter(c.city or "(unknown)" for c in customers)
    return dict(sorted(counts.items(), key=lambda item: (-item[1], item[0])))


def email_domains(customers: list[Customer]) -> list[str]:
    return sorted({c.email.split("@", 1)[1] for c in customers})


def render(customers: list[Customer]) -> str:
    lines = [f"{len(customers)} customers", "", "per city:"]
    lines += [f"  {city:<20} {count}" for city, count in customers_per_city(customers).items()]
    lines += ["", "email domains: " + ", ".join(email_domains(customers))]
    return "\n".join(lines)

"""CustomerDB: the customers in memory, persisted through a JsonStore."""

from __future__ import annotations

import os

from customerdb.models import Customer
from customerdb.search import matches
from customerdb.storage import JsonStore


class CustomerDB:
    """Loads the whole file on open, writes it back on save()."""

    def __init__(self, path: str | os.PathLike[str]) -> None:
        self.store = JsonStore(path)
        self._customers: dict[int, Customer] = {c.id: c for c in self.store.load()}

    def add(self, name: str, email: str, city: str = "") -> Customer:
        new_id = max(self._customers, default=0) + 1
        customer = Customer(new_id, name, email, city)
        customer.validate()
        self._customers[new_id] = customer
        return customer

    def get(self, customer_id: int) -> Customer | None:
        return self._customers.get(customer_id)

    def update(self, customer_id: int, **fields: str) -> Customer:
        customer = self._customers[customer_id]
        for key, value in fields.items():
            if key == "id" or not hasattr(customer, key):
                raise AttributeError(f"cannot update field {key!r}")
            setattr(customer, key, value)
        customer.validate()
        return customer

    def delete(self, customer_id: int) -> bool:
        return self._customers.pop(customer_id, None) is not None

    def all(self) -> list[Customer]:
        return sorted(self._customers.values(), key=lambda c: c.id)

    def find(self, text: str) -> list[Customer]:
        return [c for c in self.all() if matches(c, text)]

    def save(self) -> None:
        self.store.save(self.all())

"""Command line: python -m customerdb [--db FILE] {list,add,get,update,delete,find,report} ..."""

from __future__ import annotations

import argparse
import sys

from customerdb.db import CustomerDB
from customerdb.models import Customer, ValidationError
from customerdb.report import render


def show(customer: Customer) -> None:
    print(f"{customer.id:4}  {customer.name:<20} {customer.email:<28} {customer.city}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="customerdb")
    parser.add_argument("--db", default="customers.json", help="JSON file (default: %(default)s)")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    sub.add_parser("report")
    p = sub.add_parser("add")
    p.add_argument("name")
    p.add_argument("email")
    p.add_argument("--city", default="")
    p = sub.add_parser("get")
    p.add_argument("id", type=int)
    p = sub.add_parser("update")
    p.add_argument("id", type=int)
    p.add_argument("--name")
    p.add_argument("--email")
    p.add_argument("--city")
    p = sub.add_parser("delete")
    p.add_argument("id", type=int)
    p = sub.add_parser("find")
    p.add_argument("text")
    return parser


def run(db: CustomerDB, args: argparse.Namespace) -> int:
    if args.cmd == "list":
        for c in db.all():
            show(c)
    elif args.cmd == "report":
        print(render(db.all()))
    elif args.cmd == "add":
        show(db.add(args.name, args.email, args.city))
        db.save()
    elif args.cmd == "get":
        customer = db.get(args.id)
        if customer is None:
            print(f"no customer {args.id}", file=sys.stderr)
            return 1
        show(customer)
    elif args.cmd == "update":
        fields = {k: v for k in ("name", "email", "city") if (v := getattr(args, k)) is not None}
        try:
            show(db.update(args.id, **fields))
        except KeyError:
            print(f"no customer {args.id}", file=sys.stderr)
            return 1
        db.save()
    elif args.cmd == "delete":
        if not db.delete(args.id):
            print(f"no customer {args.id}", file=sys.stderr)
            return 1
        db.save()
    elif args.cmd == "find":
        for c in db.find(args.text):
            show(c)
    return 0


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return run(CustomerDB(args.db), args)
    except ValidationError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

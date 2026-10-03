#!/usr/bin/env python3
"""Enforce the source-only rule: no binary files, no symlinks leaving the tree.

  check-sources.py DIR...          fail (exit 1) listing every violation
  check-sources.py --strip DIR...  delete binary files instead (vendor step)

A file counts as binary when it contains a NUL byte (images, archives,
compiled objects, wasm, …). Empty files are fine.

Stripping a file inside a vendored Rust crate also drops it from the crate's
.cargo-checksum.json, which cargo checks file by file (these are e.g. the
Windows import libraries of windows-* crates, never built on Linux).
"""
import json
import os
import sys


def drop_cargo_checksum(path):
    d = os.path.dirname(path)
    while d and d != os.path.dirname(d):
        sums = os.path.join(d, ".cargo-checksum.json")
        if os.path.isfile(sums):
            with open(sums) as f:
                data = json.load(f)
            data["files"].pop(os.path.relpath(path, d), None)
            with open(sums, "w") as f:
                json.dump(data, f)
            return
        d = os.path.dirname(d)


def is_binary(path):
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            if b"\0" in chunk:
                return True
    return False


def scan(top, strip):
    bad = []
    top_real = os.path.realpath(top)
    for dirpath, dirnames, filenames in os.walk(top):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames + [d for d in dirnames if os.path.islink(os.path.join(dirpath, d))]:
            path = os.path.join(dirpath, name)
            if os.path.islink(path):
                target = os.path.realpath(path)
                if not target.startswith(top_real + os.sep):
                    bad.append(f"symlink out of tree: {path} -> {os.readlink(path)}")
                continue
            if is_binary(path):
                if strip:
                    os.remove(path)
                    drop_cargo_checksum(path)
                    print(f"stripped {os.path.relpath(path, top)}")
                else:
                    bad.append(f"binary: {path}")
    return bad


def main():
    args = sys.argv[1:]
    strip = "--strip" in args
    dirs = [a for a in args if a != "--strip"] or ["."]
    bad = [b for d in dirs for b in scan(d, strip)]
    for b in bad:
        print(b, file=sys.stderr)
    if bad:
        print(f"{len(bad)} violation(s) of the source-only rule", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

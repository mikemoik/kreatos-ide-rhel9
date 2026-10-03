#!/usr/bin/env python3
"""prune-crates.py SRC_DIR CRATES_DIR PACKAGE... — stub vendored crates never built.

`cargo vendor` copies every crate in Cargo.lock, including the Windows, macOS
and wasm ones (windows-sys, web-sys, …: tens of MB). Cargo still needs their
manifests to resolve the lockfile, but never compiles them on Linux. The same
goes for test-only (dev) dependencies and for crates only other workspace
members need (e.g. ruff's wasm playground). So for every crate outside the
x86_64 Linux build graph of PACKAGE... (`cargo metadata --filter-platform`,
all features, normal + build dependencies) this keeps Cargo.toml, replaces the
sources by empty stubs at the paths the manifest names, and empties the file
list in .cargo-checksum.json. Prints the stubbed directory names.

Runs at vendor time on the connected machine (needs cargo + Python >= 3.11).
"""
import json
import os
import shutil
import subprocess
import sys
import tomllib

PLATFORM = "x86_64-unknown-linux-gnu"


def linux_graph(src, roots):
    meta = json.loads(subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--locked", "--all-features",
         "--filter-platform", PLATFORM],
        cwd=src, check=True, capture_output=True, text=True).stdout)
    by_id = {p["id"]: p for p in meta["packages"]}
    nodes = {n["id"]: n for n in meta["resolve"]["nodes"]}
    members = set(meta["workspace_members"])
    todo = [i for i in members if by_id[i]["name"] in roots]
    missing = set(roots) - {by_id[i]["name"] for i in todo}
    if missing:
        sys.exit(f"packages not in workspace: {sorted(missing)}")
    seen = set()
    while todo:
        i = todo.pop()
        if i in seen:
            continue
        seen.add(i)
        for dep in nodes[i]["deps"]:
            if any(k["kind"] in (None, "build") for k in dep["dep_kinds"]):
                todo.append(dep["pkg"])
    return {(by_id[i]["name"], by_id[i]["version"]) for i in seen}


def stub(crate_dir):
    with open(os.path.join(crate_dir, "Cargo.toml"), "rb") as f:
        manifest = tomllib.load(f)
    keep = {"Cargo.toml", ".cargo-checksum.json"}
    for entry in os.listdir(crate_dir):
        if entry not in keep:
            path = os.path.join(crate_dir, entry)
            shutil.rmtree(path) if os.path.isdir(path) and not os.path.islink(path) else os.remove(path)

    # empty sources wherever the manifest points, so it still loads
    files = {manifest.get("lib", {}).get("path", "src/lib.rs"): ""}
    build = manifest.get("package", {}).get("build")
    if isinstance(build, str):
        files[build] = "fn main() {}\n"
    default_dir = {"bin": "src/bin", "example": "examples", "test": "tests", "bench": "benches"}
    for kind, folder in default_dir.items():
        for target in manifest.get(kind, []):
            path = target.get("path") or f"{folder}/{target['name']}.rs"
            files[path] = "fn main() {}\n"
    for rel, text in files.items():
        path = os.path.join(crate_dir, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    sums_path = os.path.join(crate_dir, ".cargo-checksum.json")
    with open(sums_path) as f:
        sums = json.load(f)
    sums["files"] = {}
    with open(sums_path, "w") as f:
        json.dump(sums, f)


def main():
    src, crates, roots = sys.argv[1], sys.argv[2], sys.argv[3:]
    if not roots:
        sys.exit(__doc__)
    used = linux_graph(src, roots)
    for entry in sorted(os.listdir(crates)):
        crate_dir = os.path.join(crates, entry)
        with open(os.path.join(crate_dir, "Cargo.toml"), "rb") as f:
            pkg = tomllib.load(f)["package"]
        if (pkg["name"], pkg["version"]) not in used:
            stub(crate_dir)
            print(entry)


if __name__ == "__main__":
    main()

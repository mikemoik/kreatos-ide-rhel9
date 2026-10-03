#!/usr/bin/env python3
"""gen-inventory.py — rewrite the "Third-party software" section of README.md.

Reads VERSIONS (name, upstream URL, pin) and determines each component's
license: Rust crates from their Cargo.toml `license` field, everything else
from its license file(s), recognised by their wording. Licenses that cannot
be recognised come from manifest/licenses.tsv (name <TAB> SPDX expression).
The section between the inventory markers in README.md is replaced; the run
fails if a license stays unknown.

Runs at the end of scripts/vendor-update.sh (needs Python >= 3.11).
"""
import os
import re
import sys
import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
V = os.path.join(ROOT, "vendor")
START, END = "<!-- inventory:start -->", "<!-- inventory:end -->"

LICENSE_FILE = re.compile(r"^(licen[cs]e|copying|copyright|unlicense)([-._].*)?$", re.I)

# (SPDX id, test on the normalised license text). The copyleft licenses are
# recognised by their title only (h = the first 300 characters): the GPL text
# itself mentions the LGPL, the MPL text names the GPL/LGPL as "secondary
# licenses", Vim's license refers to the GPL.
RULES = [
    ("Apache-2.0", lambda t, h: "apache license" in t and "version 2.0" in t),
    ("MPL-2.0", lambda t, h: "mozilla public license" in h and "2.0" in h),
    ("LGPL-2.1", lambda t, h: "gnu lesser general public license" in h and "2.1" in h),
    ("LGPL-3.0", lambda t, h: "gnu lesser general public license" in h),
    ("GPL-3.0", lambda t, h: "gnu general public license" in h and "version 3" in h
        and "lesser" not in h),
    ("GPL-2.0", lambda t, h: "gnu general public license" in h and "version 2" in h
        and "lesser" not in h),
    ("Unlicense", lambda t, h: "free and unencumbered software released into the public domain" in t),
    ("0BSD", lambda t, h: "permission to use, copy, modify, and/or distribute" in t and "notice" not in t.split("permission")[1][:200]),
    ("ISC", lambda t, h: "permission to use, copy, modify, and/or distribute" in t
        or "permission to use, copy, modify, and distribute this software for any purpose" in t),
    ("MIT", lambda t, h: "permission is hereby granted, free of charge" in t),
    ("BSD-3-Clause", lambda t, h: "redistribution and use in source and binary forms" in t and "neither the name" in t),
    ("BSD-2-Clause", lambda t, h: "redistribution and use in source and binary forms" in t),
    ("Zlib", lambda t, h: "this software is provided 'as-is'" in t),
    ("Vim", lambda t, h: "vim license" in t),
    ("CC0-1.0", lambda t, h: "cc0" in t or "creative commons zero" in t),
    ("BSL-1.0", lambda t, h: "boost software license" in t),
]


def classify(text):
    t = re.sub(r"[\s#*=-]+", " ", text.lower()).strip()
    h = t[:300]
    found = []
    for spdx, test in RULES:
        try:
            if test(t, h):
                found.append(spdx)
        except IndexError:
            pass
    if "0BSD" in found:
        found = [f for f in found if f != "ISC"]
    if "BSD-3-Clause" in found:
        found.remove("BSD-2-Clause")
    if "LGPL-2.1" in found and "LGPL-3.0" in found:
        found.remove("LGPL-3.0")
    return found


def license_of_dir(path):
    """SPDX expression from the license files at the top of a source tree."""
    ids = []
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isfile(full) and LICENSE_FILE.match(entry):
            with open(full, errors="replace") as f:
                for spdx in classify(f.read()):
                    if spdx not in ids:
                        ids.append(spdx)
    if not ids:
        return None
    # several license files side by side are the usual dual licensing
    return ids[0] if len(ids) == 1 else (" AND " if "Vim" in ids else " OR ").join(ids)


def license_of_crate(path):
    with open(os.path.join(path, "Cargo.toml"), "rb") as f:
        pkg = tomllib.load(f)["package"]
    lic = pkg.get("license")
    if lic:
        return lic.replace("/", " OR ")
    return license_of_dir(path)


def read_overrides():
    path = os.path.join(ROOT, "manifest", "licenses.tsv")
    over = {}
    if os.path.exists(path):
        for line in open(path):
            if line.strip() and not line.startswith("#"):
                name, spdx = line.rstrip("\n").split("\t")[:2]
                over[name] = spdx
    return over


def source_dir(name):
    kind, _, rest = name.partition("/")
    return {
        "neovim": lambda: os.path.join(V, "neovim"),
        "neovim-dep": lambda: os.path.join(V, "neovim-deps", rest),
        "plugin": lambda: os.path.join(V, "plugins", rest),
        "grammar": lambda: os.path.join(V, "grammars", rest),
        "tool": lambda: os.path.join(V, "tools", rest),
        "crate": lambda: os.path.join(V, "crates", rest),
    }[kind]()


def main():
    over = read_overrides()
    rows, crates, unknown = [], {}, []
    for line in open(os.path.join(ROOT, "VERSIONS")):
        name, url, pin = line.rstrip("\n").split(None, 2)
        path = source_dir(name)
        if name.startswith("crate/"):
            lic = over.get(name) or license_of_crate(path)
        else:
            lic = over.get(name) or license_of_dir(path)
        if not lic:
            unknown.append(name)
            lic = "?"
        if name.startswith("crate/"):
            _, tool, crate = name.split("/", 2)
            crates.setdefault(tool, []).append((crate, lic, "stub" in pin))
        else:
            rows.append((name, url, pin, lic))

    out = [START, "", "## Third-party software", "",
           "Everything vendored in this repo, with the pinned upstream version and its",
           "license. Generated from `VERSIONS` by `scripts/gen-inventory.py` (run by",
           "`scripts/vendor-update.sh`); do not edit by hand.", "",
           "| Component | Upstream | Version / commit | License |", "|---|---|---|---|"]
    for name, url, pin, lic in rows:
        short = pin if len(pin) < 20 else pin[:12]
        if pin.startswith("sha256:"):
            short = "tarball, " + pin[:19] + "…"
        shown = "none declared upstream" if lic == "NOASSERTION" else lic
        out.append(f"| {name} | <{url}> | `{short}` | {shown} |")
    for tool, items in crates.items():
        built = [c for c in items if not c[2]]
        stubs = [c for c in items if c[2]]
        out += ["", f"<details><summary>Rust crates of {tool}: {len(built)} built, "
                f"{len(stubs)} manifest-only stubs (pinned by its Cargo.lock)</summary>", "",
                "| Crate | License | Built |", "|---|---|---|"]
        for crate, lic, stub in items:
            out.append(f"| {crate} | {lic} | {'no (stub)' if stub else 'yes'} |")
        out += ["", "</details>"]
    out += ["", END]

    readme = os.path.join(ROOT, "README.md")
    text = open(readme).read()
    block = "\n".join(out)
    if START in text:
        text = text[:text.index(START)] + block + text[text.index(END) + len(END):]
    else:
        text = text.rstrip("\n") + "\n\n" + block + "\n"
    open(readme, "w").write(text)

    if unknown:
        print("license not recognised (add to manifest/licenses.tsv):", *unknown, sep="\n  ", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

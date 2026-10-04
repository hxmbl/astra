#!/usr/bin/env python3
"""Find attribute paths that two different modules assign literally.

Not a Nix parser. It works on the shape of these files: an assignment
`<dotted.path> = ...;` inside a `config = { ... }` or `options.x = { ... }`
block, in files that are not the ones obviously meant to be the sole owner
(home/, lib/, flake.nix).

Two modules assigning the same path is a hard eval error in NixOS ("conflicting
definition values"), so this is the mistake worth catching mechanically. It
produces false positives for paths that are inside `lib.mkIf`/`lib.mkMerge`
attributes and for `imports`, which is why the output is a list to read rather
than a pass/fail.
"""
import os
import re
import sys
from collections import defaultdict

ASSIGN = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_'\"]*(?:\.[A-Za-z_][A-Za-z0-9_'\"]*)*)\s*=\s*(?!=)")
DYNAMIC = re.compile(r"\$\{")


def assignments(path):
    """Yield (dotted_path, lineno) for top-ish assignments in a file."""
    out = []
    for num, line in enumerate(open(path, encoding="utf-8"), 1):
        if line.lstrip().startswith("#"):
            continue
        m = ASSIGN.match(line)
        if m:
            out.append((m.group(1), num))
    return out


def walk(d, out=None):
    out = [] if out is None else out
    for e in sorted(os.listdir(d)):
        if e in (".git", "result", ".direnv"):
            continue
        p = os.path.join(d, e)
        if os.path.isdir(p):
            walk(p, out)
        elif e.endswith(".nix"):
            out.append(p)
    return out


def main(root):
    files = walk(root)
    # These own their namespace outright; two assignments inside one of them is
    # still a bug, but two *across* them is expected.
    by_path = defaultdict(list)
    for f in files:
        for dotted, num in assignments(f):
            by_path[dotted].append((f, num))

    multi = {k: v for k, v in by_path.items() if len({f for f, _ in v}) > 1}
    print(f"{len(files)} files, {len(by_path)} distinct assignment paths")
    if not multi:
        print("no path assigned by more than one file")
        return 0
    print(f"\n{len(multi)} paths assigned by more than one file:\n")
    for dotted in sorted(multi):
        print(f"  {dotted}")
        for f, num in sorted(multi[dotted]):
            print(f"      {f}:{num}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
#!/usr/bin/env python3
"""Check that every place that lists a host lists the same hosts.

There are three: the `hosts` attrset in flake.nix, the HOST_NAMES array in
install.sh, and the matrix in .github/workflows/check.yml. They are edited by
hand, independently, and a host in one and not the others is a bad morning —
in the worst case `install.sh` offers to install a machine the flake cannot
build.

Also checks that each host's configuration.nix exists, because a host pointing
at a file that is not there only fails at evaluation time, on a push, on
someone else's machine.

Usage: host-list.py [repo-root]   (exit 0 = all consistent)
"""

import os
import re
import sys


def flake_hosts(root):
    """{name: path} from the `hosts` attrset in flake.nix.

    Indentation-agnostic on purpose: the block used to sit at six spaces and
    alejandra moved it to four, which broke a regex that anchored on the
    column. This counts braces instead of guessing at columns, so reformatting
    the tree cannot silently disarm the check.
    """
    text = open(os.path.join(root, "flake.nix"), encoding="utf-8").read()
    start = re.search(r"^\s*hosts = \{", text, re.M)
    if not start:
        sys.exit("could not find the `hosts` attrset in flake.nix")

    depth, i = 0, start.end() - 1
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    else:
        sys.exit("the `hosts` attrset in flake.nix has unbalanced braces")

    out = {}
    for line in text[start.end():i].splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        name, sep, path = line.partition("=")
        name, path = name.strip(), path.strip().rstrip(";").strip()
        if not sep or not name or not path:
            continue
        out[name] = path
    if not out:
        sys.exit("the `hosts` attrset in flake.nix looks empty")
    return out


def install_hosts(root):
    """HOST_NAMES from install.sh."""
    text = open(os.path.join(root, "install.sh"), encoding="utf-8").read()
    m = re.search(r"^HOST_NAMES=\((.*?)^\)", text, re.S | re.M)
    if not m:
        sys.exit("could not find HOST_NAMES in install.sh")
    return [
        line.split("#")[0].strip()
        for line in m.group(1).splitlines()
        if line.split("#")[0].strip()
    ]


def ci_hosts(root):
    """The `host:` matrix list from every enabled workflow."""
    found = {}
    wf_dir = os.path.join(root, ".github", "workflows")
    for fn in sorted(os.listdir(wf_dir)):
        if not fn.endswith(".yml"):
            continue
        text = open(os.path.join(wf_dir, fn), encoding="utf-8").read()
        # A fully commented-out workflow has no jobs to check; that is the
        # disabled check.yml and it is dealt with separately.
        active = re.search(r"^on:", text, re.M) is not None
        m = re.search(r"^\s*host: \[(.*?)\]", text, re.M)
        if m and active:
            found[fn] = [h.strip() for h in m.group(1).split(",") if h.strip()]
    return found


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    flakes = flake_hosts(root)
    installer = install_hosts(root)
    workflows = ci_hosts(root)

    ok = True
    # flake.nix is the reference.
    for name, path in sorted(flakes.items()):
        cfg = path.lstrip("./")
        if not os.path.isfile(os.path.join(root, cfg)):
            print(f"host-list: FAIL  {name} -> {cfg} does not exist")
            ok = False

    sets = {"flake.nix": set(flakes), "install.sh": set(installer)}
    for fn, hosts in workflows.items():
        sets[fn] = set(hosts)

    ref = sets["flake.nix"]
    for label, got in sorted(sets.items()):
        if got == ref:
            print(f"host-list: ok    {label:12} {len(got)} hosts")
            continue
        missing = sorted(ref - got)
        extra = sorted(got - ref)
        print(f"host-list: FAIL  {label} disagrees with flake.nix")
        if missing:
            print(f"              missing: {' '.join(missing)}")
        if extra:
            print(f"              not in flake.nix: {' '.join(extra)}")
        ok = False

    if len(installer) != len(set(installer)):
        print("host-list: FAIL  install.sh HOST_NAMES has a duplicate")
        ok = False

    if not workflows:
        # No workflow carries a host matrix, so there is no third list to keep
        # in sync. That is the preferred state: check.yml evaluates the whole
        # nixosConfigurations attrset, so it has no list of its own.
        print("host-list: note  no workflow carries a host matrix (nothing to sync)")

    print(f"host-list: {'all consistent' if ok else 'INCONSISTENT'} ({len(ref)} hosts)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
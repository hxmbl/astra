#!/usr/bin/env python3
"""Structural sanity check for hand-written Nix: bracket balance outside of
strings and comments, plus a few cheap smells.

Why this exists: this repo is edited without ever being evaluated, and the
failure mode that costs a morning is a stray brace or an unterminated string,
not a wrong package name.

It is NOT a parser and it does not know Nix semantics. Known limitations:

  - Inside `${ ... }` it counts braces and skips "..." strings, but it does not
    look for nested ${} inside those strings. So `${foo "${bar}"}` will be
    counted wrongly. Nothing in this repo does that.
  - It does not evaluate module options, so it cannot catch a duplicate option
    definition or a wrong option name. That is what `nix flake check` is for.

Usage: nix-balance.py [dir]
"""
import os
import sys

OPEN = {"{": "}", "[": "]", "(": ")"}
CLOSE = {v: k for k, v in OPEN.items()}


def check(path):
    s = open(path, encoding="utf-8").read()
    n = len(s)
    i, line = 0, 1
    stack = []
    errors = []

    def err(msg, ln=None):
        errors.append(f"{path}:{ln or line}: {msg}")

    def skip_interp(i, ln):
        """i points at '$' of '${'. Returns index past the matching '}'."""
        depth, j = 1, i + 2
        while j < n:
            c = s[j]
            if c == "\n":
                ln += 1
                j += 1
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                j += 1
                if depth == 0:
                    return j, ln
                continue
            elif c == "\\":
                j += 2
                continue
            elif c == '"':
                # A nested "..." string. Skip to its end without looking for
                # interpolation; see the limitation note at the top.
                j += 1
                while j < n and s[j] != '"':
                    j += 2 if s[j] == "\\" else 1
                j += 1
                continue
            elif c == "#":
                while j < n and s[j] != "\n":
                    j += 1
                continue
            j += 1
        err("unterminated ${ }", ln)
        return j, ln

    def skip_dq(i, ln):
        """i points at the opening '"'. Returns index past the closing quote."""
        i += 1
        while i < n:
            c = s[i]
            if c == "\\":
                i += 2
                continue
            if c == "\n":
                err("newline inside a \" string", ln)
                ln += 1
                i += 1
                continue
            if c == '"':
                return i + 1, ln
            if c == "$" and s[i + 1] == "{":
                i, ln = skip_interp(i, ln)
                continue
            i += 1
        err("unterminated \" string", ln)
        return i, ln

    def skip_iq(i, ln):
        """i points at the opening "''". Returns index past the closing ''."""
        i += 2
        while i < n:
            c = s[i]
            if c == "\n":
                ln += 1
                i += 1
                continue
            if s[i:i + 3] in ("''$", "'''"):
                i += 3
                continue
            if s[i:i + 2] == "''":
                return i + 2, ln
            if c == "$" and s[i + 1] == "{":
                i, ln = skip_interp(i, ln)
                continue
            i += 1
        err("unterminated '' string", ln)
        return i, ln

    while i < n:
        c = s[i]
        if c == "\n":
            line += 1
            i += 1
        elif c == "#":
            while i < n and s[i] != "\n":
                i += 1
        elif c == "/" and s[i + 1] == "*":
            i += 2
            while i < n and not (s[i] == "*" and s[i + 1] == "/"):
                if s[i] == "\n":
                    line += 1
                i += 1
            i += 2
        elif c == '"':
            i, line = skip_dq(i, line)
        elif s[i:i + 2] == "''":
            i, line = skip_iq(i, line)
        elif c in OPEN:
            stack.append((c, line))
            i += 1
        elif c in CLOSE:
            if not stack:
                err(f"stray {c}", line)
            else:
                o, ol = stack.pop()
                if o != CLOSE[c]:
                    err(f"{c} closes {o} opened at line {ol}", line)
            i += 1
        else:
            i += 1

    for o, ol in stack:
        err(f"unclosed {o} opened at line {ol}", line)

    # Cheap smells that cost a morning each.
    if s.rstrip().endswith("}"):
        pass
    for num, ln in enumerate(s.split("\n"), 1):
        stripped = ln.strip()
        if stripped.startswith("#"):
            continue
        if len(ln) - len(ln.rstrip()) and ln.rstrip().endswith(("{", ",", "+", "-", "&&", "||", "//")):
            err("trailing whitespace on a continuation line", num)
    return errors


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


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    files = walk(root)
    problems = []
    for f in files:
        problems += check(f)
    print(f"checked {len(files)} .nix files under {root}")
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print("BALANCE OK")
#!/usr/bin/env python3
"""Slice a section out of a downloaded official doc.

usage: doc-section.py <docId|filename> <start-heading> [end-heading]
"""
import os, sys

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "official", "md")

def resolve(key):
    if os.path.exists(key):
        return key
    for f in os.listdir(BASE):
        if f.startswith(key):
            return os.path.join(BASE, f)
    raise SystemExit("doc not found: " + key)

def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    path = resolve(sys.argv[1])
    t = open(path, encoding="utf-8").read()
    start = sys.argv[2]
    i = t.find(start)
    if i < 0:
        raise SystemExit("heading not found: " + start)
    end = sys.argv[3] if len(sys.argv) > 3 else None
    j = t.find(end) if end else len(t)
    if j < 0:
        j = len(t)
    sys.stdout.write(t[i:j] + "\n")

main()

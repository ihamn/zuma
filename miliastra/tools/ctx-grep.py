import os, re, sys
BASE = sys.argv[1]
pats = sys.argv[2:]
for f in sorted(os.listdir(BASE)):
    p = os.path.join(BASE, f)
    txt = open(p, encoding="utf-8").read()
    for pat in pats:
        for m in re.finditer(pat, txt):
            s = max(0, m.start()-110); e = min(len(txt), m.end()+160)
            print("### %s @%d" % (f, m.start()))
            print(txt[s:e].replace("\n", " "))
            print()

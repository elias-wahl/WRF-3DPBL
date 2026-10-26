#!/usr/bin/env python3
"""Mark what changed in the review text since an older version (Elias 2026-10-25: "switch to seeing the diff").

Both inputs come from concept_to_review_json.py. Per main section, the sentences are aligned with difflib; a changed
sentence gets "ch": "c" and its old text in "o", a new one "ch": "n", and removed old sentences are attached as "d" to
the sentence that now follows them (or to the section's "dEnd"). Section counts go to "chg" = [changed, new, removed].

Usage: python3 scripts/review_text_diff.py NEW.json OLD.json OUT.json
"""
import difflib, json, re, sys


def norm(t):
    return re.sub(r"\s+", " ", t).strip()


def main(new_p, old_p, out_p):
    new, old = json.load(open(new_p)), json.load(open(old_p))
    olds = {s["num"]: [x["t"] for b in s["blocks"] for x in b.get("s", [])] for s in old["sections"]}
    for sec in new["sections"]:
        flat = [x for b in sec["blocks"] for x in b.get("s", [])]
        A, B = olds.get(sec["num"], []), [x["t"] for x in flat]
        dEnd, counts = [], [0, 0, 0]

        def attach(j, texts):
            if not texts:
                return
            counts[2] += len(texts)
            if j < len(flat):
                flat[j].setdefault("d", []).extend(texts)
            else:
                dEnd.extend(texts)
        sm = difflib.SequenceMatcher(None, [norm(a) for a in A], [norm(b) for b in B], autojunk=False)
        for op, i1, i2, j1, j2 in sm.get_opcodes():
            if op == "equal":
                continue
            if op == "insert":
                for j in range(j1, j2):
                    flat[j]["ch"] = "n"; counts[1] += 1
                continue
            if op == "delete":
                attach(j1, A[i1:i2]); continue
            p = i1                                               # replace: pair in order by similarity
            for j in range(j1, j2):
                best, bi = 0.0, None
                for i in range(p, i2):
                    r = difflib.SequenceMatcher(None, norm(A[i]), norm(B[j]), autojunk=False).ratio()
                    if r > best:
                        best, bi = r, i
                if bi is not None and best >= 0.35:
                    attach(j, A[p:bi])
                    flat[j]["ch"], flat[j]["o"] = "c", A[bi]; counts[0] += 1
                    p = bi + 1
                else:
                    flat[j]["ch"] = "n"; counts[1] += 1
            attach(j2, A[p:i2])
        if dEnd:
            sec["dEnd"] = dEnd
        sec["chg"] = counts
    new["diffBase"] = old.get("base", "")
    json.dump(new, open(out_p, "w"), ensure_ascii=False, indent=1)
    print(out_p, "base", new["diffBase"], {s["num"]: s["chg"] for s in new["sections"]})


if __name__ == "__main__":
    main(*sys.argv[1:4])

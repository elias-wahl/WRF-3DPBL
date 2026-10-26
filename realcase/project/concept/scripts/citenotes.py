#!/usr/bin/env python3
"""Citation glosses for the review render (main_review.tex).

  citenotes.py contexts [--out DIR --chunks N]  read main_review.cocc (key|n|file|line, written by the
                                                 render) and write one JSON per chunk: id, key, n, file,
                                                 line, the sentence around the citation
  citenotes.py merge FILE.json [FILE.json ...]   add glosses {id: text} written against the current
                                                 main_review.cocc to the store citenotes.json
  citenotes.py tex                               store + citeabout.json ({key: one-line description}) -> citenotes.tex (\\citenote{key}{n}{text})
  citenotes.py missing                           occurrences without a gloss

The store citenotes.json is a list of {key, file, context, gloss}: each gloss is tied to the text around
its citation, not to its position. `tex` matches every occurrence in main_review.cocc to the stored gloss
of the same key whose context is most similar (difflib ratio >= 0.5), so edits elsewhere and added or
removed citations of the same key do not shift glosses. After editing: rebuild the render (two passes),
run `missing`, write glosses for what it lists, `merge` them, run `tex`, rebuild.
"""
import difflib
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
PC = os.path.join(os.path.dirname(HERE), 'phd_concept')

def occ():
    out = []
    for l in open(os.path.join(PC, 'main_review.cocc'), encoding='utf-8'):
        p = l.strip().split('|')
        if len(p) == 4:
            out.append(dict(id=f'{p[0]}@{p[1]}', key=p[0], n=int(p[1]), file=p[2], line=int(p[3])))
    return out

def context(o):
    path = os.path.join(PC, o['file'])
    if not os.path.exists(path):                      # citations inside \input figure files log the bare name
        path = os.path.join(PC, 'figures', o['file'])
    L = open(path, encoding='utf-8').read().split('\n')
    a, b = max(0, o['line'] - 6), min(len(L), o['line'] + 1)
    return '\n'.join(L[a:b])

STORE = os.path.join(PC, 'citenotes.json')

def load_store():
    return json.load(open(STORE, encoding='utf-8')) if os.path.exists(STORE) else []

def match():
    """occurrence id -> gloss, greedy by context similarity within each key."""
    store, out, pairs = load_store(), {}, []
    for o in occ():
        c = context(o)
        for j, e in enumerate(store):
            if e['key'] == o['key']:
                pairs.append((difflib.SequenceMatcher(None, c, e['context']).ratio() + (0.05 if e['file'] == o['file'] else 0), o['id'], j))
    used = set()
    for r, i, j in sorted(pairs, reverse=True):
        if r >= 0.5 and i not in out and j not in used:
            out[i] = store[j]['gloss']; used.add(j)
    # fallback for reworded passages: next unused gloss of the same key from the same file, in order
    for o in occ():
        if o['id'] in out: continue
        for j, e in enumerate(store):
            if j not in used and e['key'] == o['key'] and e['file'] == o['file']:
                out[o['id']] = e['gloss']; used.add(j); break
    return out

def tex_escape(s):
    for a, b in (('\\', r'\textbackslash{}'), ('&', r'\&'), ('%', r'\%'), ('$', r'\$'), ('#', r'\#'),
                 ('_', r'\_'), ('{', r'\{'), ('}', r'\}'), ('~', r'\textasciitilde{}'), ('^', r'\^{}')):
        s = s.replace(a, b)
    return s

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'missing'
    if cmd == 'contexts':
        out = sys.argv[sys.argv.index('--out') + 1] if '--out' in sys.argv else '.'
        k = int(sys.argv[sys.argv.index('--chunks') + 1]) if '--chunks' in sys.argv else 1
        oc = occ()
        for o in oc: o['context'] = context(o)
        size = -(-len(oc) // k)
        for i in range(k):
            json.dump(oc[i*size:(i+1)*size], open(os.path.join(out, f'occ_{i+1}.json'), 'w'), indent=1, ensure_ascii=False)
        print(len(oc), 'occurrences in', k, 'chunks')
    elif cmd == 'merge':
        store, cur = load_store(), {o['id']: o for o in occ()}
        for fn in sys.argv[2:]:
            for i, t in json.load(open(fn, encoding='utf-8')).items():
                o = cur[i]
                store = [e for e in store if not (e['key'] == o['key'] and e['context'] == context(o))]
                store.append(dict(key=o['key'], file=o['file'], context=context(o), gloss=t))
        json.dump(store, open(STORE, 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
        print(len(store), 'glosses in the store')
    elif cmd in ('tex', 'missing'):
        m = match()
        if cmd == 'missing':
            for o in occ():
                if o['id'] not in m: print(o['id'], o['file'], o['line'])
            print(sum(o['id'] not in m for o in occ()), 'without a gloss')
            return
        ab = os.path.join(PC, 'citeabout.json')
        about = json.load(open(ab, encoding='utf-8')) if os.path.exists(ab) else {}
        with open(os.path.join(PC, 'citenotes.tex'), 'w', encoding='utf-8') as f:
            f.write('% generated by ../scripts/citenotes.py tex from citenotes.json + citeabout.json -- do not edit\n')
            for o in occ():
                if o['id'] in m:
                    a = f"\\cgabout{{{tex_escape(about[o['key']])}}}" if o['key'] in about else ''
                    f.write(f"\\citenote{{{o['key']}}}{{{o['n']}}}{{{a}{tex_escape(m[o['id']])}}}\n")
        miss = sorted({o['key'] for o in occ()} - set(about))
        if miss: print('no about-sentence for:', ' '.join(miss))
        print(len(m), 'of', len(occ()), 'occurrences glossed')

if __name__ == '__main__':
    main()

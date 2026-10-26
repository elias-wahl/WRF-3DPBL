#!/usr/bin/env python
"""Literature gap check: rank papers connected to a .bib but missing from it.

Method (bibliographic coupling + co-citation on OpenAlex, no API key):
  1. Every DOI in the .bib is a seed.  Seeds are resolved to OpenAlex works.
  2. For every seed we collect (a) its reference list and (b) the works citing it
     (up to --max-citers per seed, newest first).
  3. Every work that is not itself in the .bib is a candidate.  Its score is
        connections = number of distinct seeds it is linked to (as reference or citer)
        score = connections * (1 + log10(1 + cited_by_count)) * recency
     with recency = 1.0 for the last 5 years, 0.8 for 5-15 years, 0.6 older.
     Connections dominate: a paper that three of your sources cite, or that cites
     three of them, matters more than a famous paper touching one.
  4. Candidates are written as a Markdown report, sorted by score, with the seeds
     they connect to, so each line can be judged against the concept.

Usage:
  python bib_gap_check.py phd_concept/references.bib [--out REPORT.md]
         [--max-citers 200] [--top 60] [--min-connections 2] [--cache cache.json]

Requires: requests.  Network access to api.openalex.org (login node).
The script never sends anything but DOIs and OpenAlex IDs.
"""
import argparse, json, math, os, re, sys, time, unicodedata
import requests

API = "https://api.openalex.org"
SESSION = requests.Session()
SESSION.headers["User-Agent"] = "bib_gap_check/1.0 (research use)"


def norm_doi(d):
    d = (d or "").strip().lower()
    return re.sub(r"^https?://(dx\.)?doi\.org/", "", d)


def norm_title(t):
    t = unicodedata.normalize("NFKD", t or "").encode("ascii", "ignore").decode()
    t = re.sub(r"\\[a-zA-Z]+|[{}$]", "", t)
    t = re.sub(r"[^a-z0-9 ]", " ", t.lower())
    return " ".join(t.split())


def parse_bib(path):
    txt = open(path, encoding="utf-8").read()
    entries = []
    for m in re.finditer(r"@(\w+)\s*\{\s*([^,\s]+)\s*,", txt):
        typ, key = m.group(1).lower(), m.group(2)
        if typ in ("comment", "preamble", "string"):
            continue
        i, depth, start = m.end(), 1, m.end()
        while i < len(txt) and depth > 0:
            depth += {"{": 1, "}": -1}.get(txt[i], 0)
            i += 1
        body = txt[start:i - 1]
        fields = {}
        for fm in re.finditer(r"(\w+)\s*=\s*(\{((?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*)\}|\"([^\"]*)\"|(\S+?))\s*(,|$)", body, re.S):
            val = fm.group(3) if fm.group(3) is not None else (fm.group(4) if fm.group(4) is not None else fm.group(5))
            fields[fm.group(1).lower()] = re.sub(r"\s+", " ", (val or "").strip())
        entries.append({"type": typ, "key": key, **fields})
    return entries


def get(url, params=None, retries=4):
    for k in range(retries):
        try:
            r = SESSION.get(url, params=params, timeout=60)
            if r.status_code == 200:
                return r.json()
            if r.status_code == 404:
                return None
            if r.status_code == 429:
                time.sleep(2 + 2 * k)
                continue
        except requests.RequestException:
            time.sleep(1 + k)
    return None


def work_by_doi(doi, cache):
    key = "doi:" + doi
    if key in cache:
        return cache[key]
    w = get(f"{API}/works/https://doi.org/{doi}",
            params={"select": "id,doi,display_name,publication_year,cited_by_count,referenced_works,primary_location"})
    cache[key] = w
    return w


def citers(openalex_id, cache, max_citers):
    key = "cites:" + openalex_id
    if key in cache:
        return cache[key]
    wid = openalex_id.rsplit("/", 1)[-1]
    out, cursor = [], "*"
    while cursor and len(out) < max_citers:
        j = get(f"{API}/works", params={"filter": f"cites:{wid}", "per-page": 200, "cursor": cursor,
                                        "sort": "publication_year:desc",
                                        "select": "id,doi,display_name,publication_year,cited_by_count,primary_location"})
        if not j:
            break
        out.extend(j.get("results", []))
        cursor = j.get("meta", {}).get("next_cursor")
    cache[key] = out[:max_citers]
    return cache[key]


def works_batch(ids, cache):
    """Resolve OpenAlex IDs (references) to metadata, 50 per request."""
    need = [i for i in ids if ("id:" + i) not in cache]
    for k in range(0, len(need), 50):
        chunk = need[k:k + 50]
        j = get(f"{API}/works", params={"filter": "openalex:" + "|".join(c.rsplit('/', 1)[-1] for c in chunk),
                                        "per-page": 50,
                                        "select": "id,doi,display_name,publication_year,cited_by_count,primary_location"})
        found = {w["id"]: w for w in (j or {}).get("results", [])}
        for c in chunk:
            cache["id:" + c] = found.get(c)
    return {i: cache.get("id:" + i) for i in ids}


def venue(w):
    loc = (w or {}).get("primary_location") or {}
    src = loc.get("source") or {}
    return src.get("display_name") or ""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("bib")
    ap.add_argument("--out", default=None)
    ap.add_argument("--max-citers", type=int, default=200)
    ap.add_argument("--top", type=int, default=60)
    ap.add_argument("--min-connections", type=int, default=2)
    ap.add_argument("--cache", default=None)
    a = ap.parse_args()

    entries = parse_bib(a.bib)
    seeds = [(e["key"], norm_doi(e["doi"])) for e in entries if e.get("doi")]
    have_doi = {d for _, d in seeds}
    have_title = {norm_title(e.get("title")) for e in entries}
    print(f"{len(entries)} entries, {len(seeds)} with DOI", file=sys.stderr)

    cache = {}
    if a.cache and os.path.exists(a.cache):
        cache = json.load(open(a.cache))

    seed_works = {}
    for key, doi in seeds:
        w = work_by_doi(doi, cache)
        if w:
            seed_works[key] = w
        else:
            print(f"  unresolved: {key} ({doi})", file=sys.stderr)
    seed_ids = {w["id"] for w in seed_works.values()}

    # connections: candidate id -> set of (seed key, relation)
    conn, meta = {}, {}
    for key, w in seed_works.items():
        for ref in w.get("referenced_works", []):
            conn.setdefault(ref, set()).add((key, "ref"))
        for c in citers(w["id"], cache, a.max_citers):
            conn.setdefault(c["id"], set()).add((key, "cites"))
            meta[c["id"]] = c
        if a.cache:
            json.dump(cache, open(a.cache, "w"))

    # resolve reference-only candidates
    unresolved = [i for i in conn if i not in meta and i not in seed_ids]
    resolved = works_batch(unresolved, cache)
    meta.update({i: w for i, w in resolved.items() if w})
    if a.cache:
        json.dump(cache, open(a.cache, "w"))

    year_now = time.gmtime().tm_year
    rows = []
    for cid, links in conn.items():
        if cid in seed_ids:
            continue
        w = meta.get(cid)
        if not w:
            continue
        doi = norm_doi(w.get("doi"))
        if (doi and doi in have_doi) or norm_title(w.get("display_name")) in have_title:
            continue
        seeds_linked = {k for k, _ in links}
        n = len(seeds_linked)
        if n < a.min_connections:
            continue
        y = w.get("publication_year") or 0
        rec = 1.0 if year_now - y <= 5 else (0.8 if year_now - y <= 15 else 0.6)
        score = n * (1 + math.log10(1 + (w.get("cited_by_count") or 0))) * rec
        rows.append((score, n, w, sorted(links)))
    rows.sort(key=lambda r: -r[0])

    lines = [f"# Literature gap report for `{os.path.basename(a.bib)}`", "",
             f"Seeds: {len(seed_works)} works with DOI resolved on OpenAlex; candidates = works cited by or citing",
             f"at least {a.min_connections} seeds and not in the .bib (matched by DOI or title). Score =",
             "connections x (1 + log10(1 + citations)) x recency. Relation: `ref` = a seed cites it,",
             "`cites` = it cites a seed. Generated by `concept/scripts/bib_gap_check.py`.", "",
             "| # | score | links | year | title | venue | DOI | connected seeds |", "|---|---|---|---|---|---|---|---|"]
    for i, (score, n, w, links) in enumerate(rows[:a.top], 1):
        title = (w.get("display_name") or "").replace("|", "/")
        doi = norm_doi(w.get("doi"))
        doi_md = f"[{doi}](https://doi.org/{doi})" if doi else ""
        linkstr = ", ".join(f"{k}({r})" for k, r in links)
        lines.append(f"| {i} | {score:.1f} | {n} | {w.get('publication_year','')} | {title} | {venue(w)} | {doi_md} | {linkstr} |")
    report = "\n".join(lines) + "\n"
    if a.out:
        open(a.out, "w").write(report)
        print(f"wrote {a.out} ({len(rows)} candidates, top {min(a.top, len(rows))})", file=sys.stderr)
    else:
        print(report)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Download papers by DOI through an institutional connection (university VPN).

What it does, per DOI:
  1. Crossref metadata (title, first author, year, journal) -> a Zotero-style file name
     "Author et al. - Year - Title.pdf".
  2. Resolve https://doi.org/<doi> with a browser-like session (cookies kept) to the
     publisher's landing page.
  3. Try PDF URLs in this order: Crossref "link" entries of type application/pdf, the
     <meta name="citation_pdf_url"> tag of the landing page, then publisher patterns
     (AMS, Wiley/AGU, Springer, MDPI, Frontiers, Copernicus, Elsevier, Sciendo, ETH).
  4. Accept a download only if the payload starts with %PDF and does not come from a
     "preview" URL (AMS serves a two-page previewpdf to readers without access; that file is
     kept as *.preview.pdf, status "preview", and the full-text downloadpdf URL is tried next).
  5. Write results.csv (doi, status, file) in the output folder; skip DOIs already done.

Usage (on the laptop, VPN on):
  pip install requests
  python fetch_papers.py --list gap_dois.txt --out ./papers
  python fetch_papers.py 10.1002/qj.71 10.3390/atmos9030102 --out ./papers
Options: --delay 2 (seconds between requests), --unpaywall you@uni.example (also try
open-access copies via Unpaywall; your address is sent to that service only if you set it),
--retry-failed (re-run DOIs marked failed or preview in results.csv).

Only requests is required.  Nothing is uploaded anywhere.\nKnown limits: Wiley/AGU, MDPI and AMS sit behind Cloudflare and may answer 403 to any script,\nVPN or not; the run ends with a list of those DOIs to open in the browser (Zotero connector).
"""
import argparse, csv, os, re, sys, time, unicodedata
from urllib.parse import urlparse, urljoin
import requests

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
S = requests.Session()
S.headers.update({"User-Agent": UA, "Accept": "text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8",
                  "Accept-Language": "en-US,en;q=0.9"})


def clean(s, n=110):
    s = unicodedata.normalize("NFKC", s or "")
    s = re.sub(r"<[^>]+>", "", s)               # strip tags in Crossref titles
    s = re.sub(r'[\\/:*?"<>|]+', " ", s)         # illegal filename characters
    s = re.sub(r"\s+", " ", s).strip(" .")
    return s[:n].rstrip(" .")


def crossref(doi):
    try:
        r = S.get(f"https://api.crossref.org/works/{doi}", timeout=30,
                  headers={"Accept": "application/json"})
        if r.status_code != 200:
            return {}
        m = r.json()["message"]
    except Exception:
        return {}
    authors = m.get("author") or []
    fam = [a.get("family") or a.get("name") or "" for a in authors]
    if len(fam) == 0:
        who = "Unknown"
    elif len(fam) == 1:
        who = fam[0]
    elif len(fam) == 2:
        who = f"{fam[0]} and {fam[1]}"
    else:
        who = f"{fam[0]} et al."
    year = ""
    for k in ("published-print", "published-online", "issued", "created"):
        parts = (m.get(k) or {}).get("date-parts") or [[None]]
        if parts and parts[0] and parts[0][0]:
            year = str(parts[0][0]); break
    title = (m.get("title") or [""])[0]
    pdf_links = [l["URL"] for l in m.get("link", []) if "pdf" in (l.get("content-type") or "")]
    return {"who": who, "year": year, "title": title, "journal": (m.get("container-title") or [""])[0],
            "pdf_links": pdf_links}


def landing(doi):
    r = S.get(f"https://doi.org/{doi}", timeout=60, allow_redirects=True)
    return r.url, (r.text if "html" in (r.headers.get("Content-Type") or "") else ""), r


def publisher_candidates(doi, url, html):
    c = []
    m = re.search(r'<meta[^>]+name=["\']citation_pdf_url["\'][^>]+content=["\']([^"\']+)', html, re.I) or \
        re.search(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']citation_pdf_url["\']', html, re.I)
    if m:
        c.append(urljoin(url, m.group(1)))
    host = urlparse(url).netloc.lower()
    path = urlparse(url).path
    if "ametsoc.org" in host:
        # landing: https://journals.ametsoc.org/view/journals/<j>/<v>/<i>/<id>.xml
        # full text: https://journals.ametsoc.org/downloadpdf/view/journals/<j>/<v>/<i>/<id>.pdf
        # (the citation_pdf_url meta tag points to .../previewpdf/... without access: 2 pages)
        if "/journals/" in path:
            tail = path.split("/journals/")[-1]
            tail_pdf = re.sub(r"\.xml$", ".pdf", tail)
            c.append(f"https://journals.ametsoc.org/downloadpdf/view/journals/{tail_pdf}")
            c.append(f"https://journals.ametsoc.org/downloadpdf/journals/{tail_pdf}")
            c.append(f"https://journals.ametsoc.org/view/journals/{tail_pdf}")
        # move preview links to the end so a full-text candidate wins when it is reachable
        c = [u for u in c if "previewpdf" not in u] + [u for u in c if "previewpdf" in u]
    if "wiley.com" in host or "agupubs" in host:
        c.append(f"https://{host}/doi/pdfdirect/{doi}?download=true")
        c.append(f"https://{host}/doi/pdf/{doi}")
    if "springer.com" in host or "link.springer" in host:
        c.append(f"https://link.springer.com/content/pdf/{doi}.pdf")
    if "mdpi.com" in host:
        c.append(re.sub(r"/htm$", "", url).rstrip("/") + "/pdf")
    if "frontiersin.org" in host:
        c.append(f"https://www.frontiersin.org/articles/{doi}/pdf")
    if "copernicus.org" in host:
        # https://wes.copernicus.org/articles/8/1251/2023/  ->  .../wes-8-1251-2023.pdf
        m2 = re.match(r"https?://([a-z]+)\.copernicus\.org/articles/(\d+)/(\d+)/(\d{4})/?", url)
        if m2:
            j, v, p, y = m2.groups()
            c.append(f"https://{j}.copernicus.org/articles/{v}/{p}/{y}/{j}-{v}-{p}-{y}.pdf")
    if "sciencedirect.com" in host:
        c.append(url.split("?")[0].rstrip("/") + "/pdfft?isDTMRedir=true&download=true")
    if "sciendo.com" in host or "degruyter" in host:
        m3 = re.search(r'href=["\']([^"\']+\.pdf[^"\']*)', html)
        if m3:
            c.append(urljoin(url, m3.group(1)))
    if "research-collection.ethz.ch" in host or "ethz" in host:
        for m4 in re.finditer(r'href=["\']([^"\']+/download[^"\']*|[^"\']+\.pdf[^"\']*)', html):
            c.append(urljoin(url, m4.group(1)))
    return [u for u in dict.fromkeys(c) if u]


def unpaywall(doi, email):
    try:
        r = S.get(f"https://api.unpaywall.org/v2/{doi}", params={"email": email}, timeout=30)
        if r.status_code != 200:
            return []
        j = r.json()
        out = []
        for loc in ([j.get("best_oa_location")] + (j.get("oa_locations") or [])):
            if loc and loc.get("url_for_pdf"):
                out.append(loc["url_for_pdf"])
        return list(dict.fromkeys(out))
    except Exception:
        return []


def try_download(url, dest, referer=None):
    try:
        h = {"Accept": "application/pdf,*/*;q=0.8"}
        if referer:
            h["Referer"] = referer
        r = S.get(url, timeout=120, allow_redirects=True, headers=h, stream=True)
        head = r.raw.read(5, decode_content=True) if hasattr(r, "raw") else b""
        body = head + r.raw.read(decode_content=True)
        if r.status_code == 200 and body[:4] == b"%PDF":
            with open(dest, "wb") as f:
                f.write(body)
            return True, f"{len(body)//1024} kB"
        return False, f"HTTP {r.status_code}, {(r.headers.get('Content-Type') or '?').split(';')[0]}"
    except Exception as e:
        return False, f"error {type(e).__name__}"


def read_list(path):
    dois = []
    for line in open(path, encoding="utf-8"):
        line = line.split("#")[0].strip()
        if not line:
            continue
        m = re.search(r"10\.\d{4,9}/\S+", line)
        if m:
            dois.append(m.group(0).rstrip(".,;"))
    return dois


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dois", nargs="*")
    ap.add_argument("--list", help="text file with one DOI per line (comments after #)")
    ap.add_argument("--out", default="papers")
    ap.add_argument("--delay", type=float, default=2.0)
    ap.add_argument("--unpaywall", default=None, metavar="EMAIL")
    ap.add_argument("--retry-failed", action="store_true")
    a = ap.parse_args()

    dois = list(a.dois)
    if a.list:
        dois += read_list(a.list)
    dois = list(dict.fromkeys(d.lower() for d in dois))
    if not dois:
        sys.exit("no DOIs given")
    os.makedirs(a.out, exist_ok=True)
    results_path = os.path.join(a.out, "results.csv")
    done = {}
    if os.path.exists(results_path):
        for row in csv.DictReader(open(results_path, encoding="utf-8")):
            done[row["doi"]] = row
    log = open(results_path, "a", newline="", encoding="utf-8")
    w = csv.DictWriter(log, fieldnames=["doi", "status", "file", "detail"])
    if not done:
        w.writeheader()

    for i, doi in enumerate(dois, 1):
        prev = done.get(doi)
        if prev and (prev["status"] == "ok" or not a.retry_failed):
            print(f"[{i}/{len(dois)}] {doi}: already {prev['status']}, skipping")
            continue
        meta = crossref(doi)
        name = f"{meta.get('who') or 'Unknown'} - {meta.get('year') or 'n.d.'} - {clean(meta.get('title') or doi.replace('/', '_'))}.pdf"
        dest = os.path.join(a.out, clean(name, 200) if not name.endswith(".pdf") else name)
        print(f"[{i}/{len(dois)}] {doi}\n    {name}")
        status, detail, cands = "failed", "", []
        try:
            url, html, resp = landing(doi)
            if resp.status_code == 200 and resp.content[:4] == b"%PDF":
                open(dest, "wb").write(resp.content); status, detail = "ok", "direct"
            else:
                cands = list(meta.get("pdf_links") or []) + publisher_candidates(doi, url, html)
                if a.unpaywall:
                    cands += unpaywall(doi, a.unpaywall)
                tried = []
                for cu in dict.fromkeys(cands):
                    is_preview = "previewpdf" in cu
                    target = dest[:-4] + ".preview.pdf" if is_preview else dest
                    ok, info = try_download(cu, target, referer=url)
                    tried.append(f"{cu} -> {info}")
                    if ok and not is_preview:
                        status, detail = "ok", f"{cu} ({info})"; break
                    if ok and is_preview:
                        status, detail = "preview", f"{cu} ({info}) -- first pages only"
                    time.sleep(a.delay / 2)
                if status != "ok":
                    detail = detail if status == "preview" else ("; ".join(tried) if tried else f"no PDF link found on {url}")
                    if html:
                        open(dest[:-4] + ".landing.html", "w", encoding="utf-8").write(html)
        except Exception as e:
            detail = f"error {type(e).__name__}: {e}"
        print(f"    {status}: {detail[:160]}")
        w.writerow({"doi": doi, "status": status, "file": os.path.basename(dest) if status == "ok" else "", "detail": detail})
        log.flush()
        time.sleep(a.delay)
    log.close()
    rows = list({r["doi"]: r for r in csv.DictReader(open(results_path, encoding="utf-8"))}.values())  # last row per DOI
    ok = sum(1 for r in rows if r["status"] == "ok")
    failed = [r["doi"] for r in rows if r["status"] != "ok"]
    previews = sum(1 for r in rows if r["status"] == "preview")
    print(f"\n{ok} PDFs in {a.out}; {len(failed)} not downloaded, of which {previews} only as preview (see {results_path}).")
    if failed:
        print("Open these in the browser (VPN on) and save with the Zotero connector; Cloudflare-protected"
              " publishers (Wiley/AGU, MDPI, AMS) often refuse scripted downloads even on the VPN:")
        for d in failed:
            print(f"  https://doi.org/{d}")


if __name__ == "__main__":
    main()

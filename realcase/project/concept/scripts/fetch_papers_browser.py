#!/usr/bin/env python3
"""Download papers by DOI with a real (headed) Firefox via Playwright.

For the publishers that answer scripts with a Cloudflare / bot challenge (AMS, Wiley/AGU/RMetS,
MDPI, Springer), which `fetch_papers.py` cannot get past.  A real browser solves the JS
challenges itself; if a site shows a checkbox, click it in the window and the run continues.
Needs an institutional IP (UIBK network or VPN) for the paywalled ones.

Reuses fetch_papers.py for the Crossref metadata, the file name and the publisher PDF URL
patterns.  Per DOI: open https://doi.org/<doi>, wait out any challenge, collect PDF candidates
(citation_pdf_url, publisher patterns, Crossref links), fetch each with the browser's cookies,
and fall back to navigating to it as a download.  Only payloads starting with %PDF count; AMS
"previewpdf" (first two pages only) is rejected.

Usage (python from the `vpn` conda env, which has playwright + firefox installed):
  ~/miniconda3/envs/vpn/bin/python fetch_papers_browser.py --list dois.txt --out ./dl [--adopt]
  ~/miniconda3/envs/vpn/bin/python fetch_papers_browser.py 10.1002/qj.4281 --out ./dl
List format: one DOI per line, optional "# bibkey" comment (as in fetch_logs/*_dois.txt).
--adopt moves each download into sources/papers/ as "<bibkey> - <name>.pdf" (needs the key),
skipping keys that already have a file.  Results go to <out>/results.csv.
"""
import argparse, csv, os, re, shutil, sys
from urllib.parse import urljoin

from playwright.sync_api import sync_playwright, Error as PWError, TimeoutError as PWTimeout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fetch_papers as fp  # noqa: E402
try:  # only for --adopt; the script also runs from a copy without concept/
    from sources_index import PAPERS, files_by_key  # noqa: E402
except ImportError:
    PAPERS = files_by_key = None

PROFILE = os.path.expanduser("~/.cache/fetch_papers_firefox")  # keeps cf_clearance between runs
CHALLENGE = re.compile(r"just a moment|client challenge|attention required|verify you are human|"
                       r"access denied|checking your browser", re.I)


def read_list(path):
    out = []
    for line in open(path, encoding="utf-8"):
        doi, _, key = line.partition("#")
        if doi.strip():
            out.append((doi.strip(), key.strip() or None))
    return out


def wait_challenge(page, limit=180):
    """Wait while a bot-challenge page is shown (solve it by hand if it asks).
    AMS (AWS WAF) serves its challenge with HTTP 202 and an empty title, hence the empty-title check."""
    for i in range(limit):
        try:
            title = page.title().strip()
        except PWError:
            title = ""
        if title and not CHALLENGE.search(title) and "doi.org" not in page.url:
            return True
        if i == 5:
            print("    challenge page -- click it in the browser window if it asks")
        page.wait_for_timeout(1000)
    return False


def save_if_pdf(body, url, dest):
    if body[:4] != b"%PDF" or "previewpdf" in url:
        return False
    with open(dest, "wb") as f:
        f.write(body)
    return True


def fetch_pdf(ctx, page, url, dest, referer):
    # 1) plain request with the browser's cookies (fast, works once the challenge is passed)
    try:
        r = ctx.request.get(url, headers={"Referer": referer, "Accept": "application/pdf,*/*;q=0.8"},
                            timeout=60000)
        if r.ok and save_if_pdf(r.body(), r.url, dest):
            return True, f"request ({os.path.getsize(dest)//1024} kB)"
        why = f"request HTTP {r.status}"
    except PWError as e:
        why = f"request {type(e).__name__}"
    # 2) navigate to it; pdf.js is off, so a PDF arrives as a download (after any challenge)
    try:
        with page.expect_download(timeout=45000) as dl:
            try:
                page.goto(url, wait_until="commit", referer=referer)
            except PWError as e:
                if "Download is starting" not in str(e):
                    raise
            wait_challenge(page)
        d = dl.value
        tmp = dest + ".part"
        d.save_as(tmp)
        body = open(tmp, "rb").read()
        os.remove(tmp)
        if save_if_pdf(body, d.url, dest):
            return True, f"download ({len(body)//1024} kB)"
        return False, f"{why}; download not a full PDF ({d.url})"
    except PWTimeout:
        return False, f"{why}; no download ({page.url})"
    except PWError as e:
        return False, f"{why}; navigate {str(e).splitlines()[0][:120]}"


def adopt(dest, key):
    if PAPERS is None:
        return "not adopted (sources_index.py not found)"
    if files_by_key().get(key):
        return f"kept in out/ ({key} already in papers/)"
    target = os.path.join(PAPERS, f"{key} - {os.path.basename(dest)}")
    shutil.move(dest, target)
    return f"adopted -> papers/{os.path.basename(target)}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dois", nargs="*")
    ap.add_argument("--list")
    ap.add_argument("--out", required=True)
    ap.add_argument("--adopt", action="store_true", help="move downloads into sources/papers/ under their key")
    ap.add_argument("--headless", action="store_true", help="usually fails the challenges; for testing")
    a = ap.parse_args()
    items = [(d, None) for d in a.dois] + (read_list(a.list) if a.list else [])
    if not items:
        ap.error("no DOIs")
    os.makedirs(a.out, exist_ok=True)

    rows = []
    with sync_playwright() as p:
        ctx = p.firefox.launch_persistent_context(
            PROFILE, headless=a.headless, accept_downloads=True, viewport={"width": 1200, "height": 900},
            firefox_user_prefs={"pdfjs.disabled": True,
                                "browser.download.open_pdf_attachments_inline": False,
                                "browser.helperApps.neverAsk.saveToDisk": "application/pdf,application/octet-stream"})
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        for i, (doi, key) in enumerate(items, 1):
            meta = fp.crossref(doi)
            name = (f"{meta.get('who') or 'Unknown'} - {meta.get('year') or 'n.d.'} - "
                    f"{fp.clean(meta.get('title') or doi.replace('/', '_'))}.pdf")
            dest = os.path.join(a.out, name)
            print(f"[{i}/{len(items)}] {key or ''} {doi}\n    {name}")
            status, detail = "failed", ""
            try:
                page.goto(f"https://doi.org/{doi}", wait_until="domcontentloaded", timeout=90000)
                wait_challenge(page)
                page.wait_for_timeout(1500)
                landing = page.url
                html = page.content()
                # PDF buttons on the page itself (after the patterns, before Crossref's TDM links)
                onpage = [urljoin(landing, h) for h in re.findall(
                    r'href="([^"]*(?:/downloadpdf/|/pdfdirect/|/doi/pdf/|/content/pdf/)[^"]*)"', html)]
                cands = fp.publisher_candidates(doi, landing, html) + onpage + meta.get("pdf_links", [])
                tried = []
                for u in dict.fromkeys(cands):
                    ok, info = fetch_pdf(ctx, page, u, dest, landing)
                    tried.append(f"{u} -> {info}")
                    if ok:
                        status, detail = "ok", f"{u} {info}"
                        break
                if status != "ok":
                    detail = "; ".join(tried) or f"no PDF link found on {landing}"
            except PWError as e:
                detail = f"error {str(e).splitlines()[0][:200]}"
            if status == "ok" and a.adopt and key:
                detail += "; " + adopt(dest, key)
            print(f"    {status}: {detail[:300]}")
            rows.append({"doi": doi, "key": key or "", "status": status, "file": name if status == "ok" else "",
                         "detail": detail})
        ctx.close()

    with open(os.path.join(a.out, "results.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["doi", "key", "status", "file", "detail"])
        w.writeheader()
        w.writerows(rows)
    bad = [r for r in rows if r["status"] != "ok"]
    print(f"\n{len(rows) - len(bad)}/{len(rows)} ok" + ("; failed:\n  " + "\n  ".join(
        f"{r['key']} https://doi.org/{r['doi']}" for r in bad) if bad else ""))


if __name__ == "__main__":
    main()

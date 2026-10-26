#!/usr/bin/env python3
"""Turn the PhD concept into sections -> blocks -> sentences (JSON) for the phone review page.

Elias 2026-10-25: review the whole text on the phone and attach notes to single sentences.
Each sentence gets an id from its section and a hash of its text, so notes on unchanged
sentences survive a regeneration after edits. Floats keep only their numbered caption.

Usage: python3 scripts/concept_to_review_json.py [OUT.json]   (run from anywhere)
"""
import hashlib, json, os, re, subprocess, sys
from pathlib import Path

P = Path(os.environ.get("CONCEPT_DIR", "/gpfs/data/fs72996/ewahl/concept/phd_concept"))   # another checkout: CONCEPT_DIR=…
PANDOC = "/home/fs72996/ewahl/miniconda3/envs/smartable/bin/pandoc"
FILES = ["01_introduction", "02_state_of_research", "03_research_questions", "04_methods",
         "05_first_paper", "06_second_paper", "07_third_paper", "08_schedule"]
SCHEMES = {r"\schemeM": "MYNN", r"\schemeG": "G19", r"\schemeA": "3D-APPROX", r"\schemeF": "3D-FULL"}
ABBREV = ["et al", "e.g", "i.e", "cf", "Sect", "Sects", "Fig", "Figs", "Eq", "Eqs", "Tab", "approx", "p", "pp",
          "vs", "Dr", "No", "ca", "resp", "incl", "Ch", "Vol", "St", "Jul", "Oct", "Nov", "Dec", "Sep", "Aug"]


def balanced(s, i):
    """Index just past the brace group that opens at s[i] == '{'."""
    d = 0
    while i < len(s):
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "{":
            d += 1
        elif c == "}":
            d -= 1
            if d == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced braces")


def drop_cmd(s, name, keep):
    """Remove \\name{...} (keep=False) or replace it by its argument (keep=True)."""
    pat = re.compile(r"\\" + name + r"\{")
    while (m := pat.search(s)):
        j = balanced(s, m.end() - 1)
        s = s[:m.start()] + (s[m.end():j - 1] if keep else "") + s[j:]
    return s


def strip_comments(t):
    return "\n".join(re.sub(r"(?<!\\)%.*", "", ln) for ln in t.split("\n"))


def aux_labels():
    lab = {}
    for m in re.finditer(r"\\newlabel\{([^}]*)\}\{\{([^}]*)\}", (P / "main.aux").read_text(errors="ignore")):
        lab[m.group(1)] = m.group(2)
    return lab


def acronyms():
    acr = {}
    src = (P / "00_preamble.tex").read_text()
    for m in re.finditer(r"\\DeclareAcronym\{([^}]*)\}\{", src):
        body = src[m.end():balanced(src, m.end() - 1) - 1]
        sm = re.search(r"short=(\{[^}]*\}|[^,]*)", body)
        lm = re.search(r"long=(\{.*\}|[^,]*)", body)
        strip = lambda x: x.strip().strip("{}").strip()
        acr[m.group(1)] = (strip(sm.group(1)) if sm else m.group(1).upper(), strip(lm.group(1)) if lm else m.group(1))
        if "first-style=short" in body:
            SHORT_FIRST.add(m.group(1))
    return acr


def preprocess(t, lab, acr, used):
    t = strip_comments(t)
    t = re.sub(r"\\input\{(figures/[^}]*)\}", lambda m: strip_comments((P / (m.group(1) + ("" if m.group(1).endswith(".tex") else ".tex"))).read_text())
               if "\\begin{figure" in (P / (m.group(1) + ("" if m.group(1).endswith(".tex") else ".tex"))).read_text() else "", t)
    for name in ("expl", "todo", "open"):
        t = drop_cmd(t, name, keep=False)
    for name in ("rev", "revb", "revc", "revd", "reve", "revf", "revg"):
        t = drop_cmd(t, name, keep=True)

    def floats(m):
        env, body = m.group(1), m.group(2)
        kind = "Table" if env.startswith("table") else "Figure"
        lm = re.search(r"\\label\{([^}]*)\}", body)
        num = lab.get(lm.group(1), "?") if lm else "?"
        cm = re.search(r"\\caption\{", body)
        cap = body[cm.end():balanced(body, cm.end() - 1) - 1] if cm else ""
        return f"\n\n\\textbf{{{kind} {num}:}} {cap}\n\n"
    t = re.sub(r"\\begin\{(figure\*?|table\*?)\}.*?\n(.*?)\\end\{\1\}", floats, t, flags=re.S)
    t = re.sub(r"\\eqref\{([^}]*)\}", lambda m: "(" + lab.get(m.group(1), "?") + ")", t)
    t = re.sub(r"\\(?:ref|autoref)\{([^}]*)\}", lambda m: lab.get(m.group(1), "?"), t)
    for k, v in SCHEMES.items():
        t = re.sub(re.escape(k) + r"(\{\})?", v, t)
    t = t.replace(r"\qsq", "q^{2}").replace(r"\dx", r"\Delta x")
    t = t.replace(r"\mss", r"\,\si{\metre\squared\per\second\squared}").replace(r"\ms", r"\,\si{\metre\per\second}")
    t = re.sub(r"\\RQ\{([^}]*)\}", r"\\textbf{RQ~\1}", t)

    def ac(m):
        cmd, key = m.group(1), m.group(2)
        short, long = acr.get(key, (key.upper(), key))
        long = long.replace("--", "–")
        plural = cmd.endswith("p")
        s, l = short + ("s" if plural else ""), long + ("s" if plural else "")
        if cmd.startswith("acs"):
            out = s
        elif cmd.startswith("acl"):
            out = l
        elif key in SHORT_FIRST and not cmd.startswith("acf"):
            out = s
        elif cmd.startswith("acf") or key not in used:
            out = f"{l} ({s})"
        else:
            out = s
        if cmd in ("ac", "acp", "acf", "acs", "acl"):
            used.add(key)
        if m.group(0)[1].isupper():
            out = out[0].upper() + out[1:]
        return out
    t = re.sub(r"\\([Aa]c(?:s|l|f)?p?)\{([^}]*)\}", lambda m: ac(m) if m.group(1)[0] == "a" else ac_cap(m, ac), t)
    t = re.sub(r"\\textsc\{([^}]*)\}", lambda m: m.group(1).upper(), t)
    return t


def ac_cap(m, ac):
    out = ac(m)
    return out[0].upper() + out[1:]


def to_markdown(tex):
    hdr = "\\newcommand{\\ganttbar}[1]{}\n"
    r = subprocess.run([PANDOC, "-f", "latex", "-t", "markdown-smart-raw_tex-raw_attribute-bracketed_spans-native_spans-link_attributes-header_attributes",
                        "--wrap=none", "--citeproc", "--bibliography", str(P / "references.bib"),
                        "--metadata", "suppress-bibliography=true", "--metadata", "link-citations=false"],
                       input=hdr + tex, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr)
    return r.stdout


UNITS = {"metre": "m", "second": "s", "hour": "h", "kelvin": "K", "watt": "W", "pascal": "Pa", "gram": "g",
         "minute": "min", "day": "d", "percent": "\\%", "degree": "^{\\circ}", "joule": "J", "radian": "rad"}
PREFIX = {"kilo": "k", "hecto": "h", "milli": "m", "centi": "c", "mega": "M", "micro": "\\mu "}
SUP = str.maketrans("0123456789", "⁰¹²³⁴⁵⁶⁷⁸⁹")


def si_math(u):
    """siunitx unit macros -> MathJax text, e.g. \\metre\\per\\second -> m\\,s^{-1}."""
    out, per, pre, power = [], False, "", ""
    for w in re.findall(r"\\([A-Za-z]+)", u):
        if w == "per":
            per = True
        elif w in PREFIX:
            pre = PREFIX[w]
        elif w in ("squared", "cubed"):
            power = "2" if w == "squared" else "3"
            if out:
                out[-1] = out[-1][0], out[-1][1], power
        elif w in UNITS:
            out.append((pre + UNITS[w], per, ""))
            pre, per = "", False
    parts = []
    for name, neg, pw in out:
        e = ("-" if neg else "") + (pw or ("1" if neg else ""))
        parts.append(name + ("^{%s}" % e if e else ""))
    return "\\mathrm{" + "\\,".join(parts) + "}"


def si_in_math(x):
    x = re.sub(r"\\SI\{([^}]*)\}\{([^}]*)\}", lambda m: m.group(1) + "\\," + si_math(m.group(2)), x)
    return re.sub(r"\\si\{([^}]*)\}", lambda m: si_math(m.group(1)), x)


MATH = re.compile(r"\$\$.+?\$\$|\$[^$]+\$", re.S)


def clean_md(s):
    """Markdown escapes and link syntax away, math untouched."""
    parts, last, out = [], 0, []
    for m in MATH.finditer(s):
        parts.append((False, s[last:m.start()])); parts.append((True, m.group(0))); last = m.end()
    parts.append((False, s[last:]))
    for is_math, x in parts:
        if is_math:
            x = si_in_math(x)
        if is_math and x.startswith("$$"):                            # display math: number it as in the PDF
            lm = re.search(r"\\label\{([^}]*)\}", x)
            tag = "\\tag{%s}" % LAB.get(lm.group(1), "") if lm else ""
            x = re.sub(r"\\label\{[^}]*\}|\\(begin|end)\{equation\*?\}", "", x)
            x = x[:-2].rstrip() + (" " + tag if tag else "") + "$$"
        if not is_math:
            x = re.sub(r"</?span[^>]*>", "", x)
            x = re.sub(r"\[\^(\d+)\](?!:)", lambda m: m.group(1).translate(SUP), x)      # footnote markers
            x = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", x)          # [text](link) -> text
            x = re.sub(r"\{[#.][^}]*\}", "", x)                       # leftover attributes
            x = re.sub(r"\\([\\`*_{}\[\]()#+\-.!$|~<>'\"@^&])", r"\1", x)
            x = x.replace("\\\n", " ")
        out.append(x)
    return re.sub(r"[ \t]+", " ", "".join(out)).strip()


def sentences(text):
    masks = []
    def keep(m):
        masks.append(m.group(0)); return f"\u0000{len(masks) - 1}\u0000"
    t = MATH.sub(keep, text)
    t = re.sub(r"\([^()]*\)", keep, t)                                # parentheses never end a sentence
    for a in ABBREV:
        t = re.sub(r"(?<![A-Za-z])" + re.escape(a) + r"\.", lambda m: m.group(0)[:-1] + "\u0001", t)
    t = re.sub(r"(?<=\b[A-Z])\.(?=\s[A-Z])", "\u0001", t)            # initials
    parts = re.split(r"(?<=[.!?:”])\s+(?=[A-Z0-9“\"(\u0000*])", t)
    out = []
    for p in parts:
        while (m := re.search("\u0000(\\d+)\u0000", p)):
            p = p[:m.start()] + masks[int(m.group(1))] + p[m.end():]
        p = p.replace("\u0001", ".").strip()
        if p:
            out.append(p)
    # a split after a colon only when what follows is a full sentence
    merged = []
    for p in out:
        if merged and merged[-1].endswith(":") and len(p) < 25:
            merged[-1] += " " + p
        else:
            merged.append(p)
    return merged


def sid(sec, text, seen):
    h = hashlib.sha1(re.sub(r"\W+", " ", text).lower().encode()).hexdigest()[:8]
    k = f"{sec}-{h}"
    seen[k] = seen.get(k, 0) + 1
    return k if seen[k] == 1 else f"{k}-{seen[k]}"


LAB = {}
SHORT_FIRST = set()


def main():
    lab, acr, used = aux_labels(), acronyms(), set()
    LAB.update(lab)
    sections, seen = [], {}
    sec_n, sub_n = 0, 0
    for f in FILES:
        tex = preprocess((P / f"{f}.tex").read_text(), lab, acr, used)

        def head(m):
            nonlocal sec_n, sub_n
            kind, star, title = m.group(1), m.group(2), m.group(3)
            if star:
                return m.group(0)
            if kind == "section":
                sec_n += 1; sub_n = 0; return f"\\section{{{sec_n} {title}}}"
            sub_n += 1
            return f"\\subsection{{{sec_n}.{sub_n} {title}}}"
        tex = re.sub(r"\\(section|subsection)(\*?)\{((?:[^{}]|\{[^{}]*\})*)\}", head, tex)
        md = to_markdown(tex)
        cur = None
        for raw in re.split(r"\n\s*\n", md):
            b = raw.strip()
            if not b or b.startswith(("<!--", ":::")):
                continue
            fm = re.match(r"\[\^(\d+)\]:\s*(.*)", b, re.S)
            if fm and cur is not None:                                # footnote text as a small block
                txt = clean_md(fm.group(2).replace("\n", " ")).replace("<", "").replace(">", "").replace("`", "")
                cur["blocks"].append({"k": "fn", "s": [{"id": sid(cur["id"], txt, seen), "t": fm.group(1).translate(SUP) + " " + txt}]})
                continue
            hm = re.match(r"(#{1,6})\s+(.*)", b)
            if hm and len(hm.group(1)) <= 2:
                title = clean_md(hm.group(2))
                if len(hm.group(1)) == 1 or cur is None:
                    num = title.split(" ", 1)[0]
                    cur = {"id": "s" + num.replace(".", "_"), "order": len(sections), "num": num,
                           "title": title.split(" ", 1)[1] if " " in title else title, "blocks": []}
                    sections.append(cur)
                else:
                    cur["blocks"].append({"k": "h", "t": title})
                continue
            lead = None
            if hm:                                                   # \paragraph{...} -> run-in lead
                lead, b = clean_md(hm.group(2)), ""
            items = re.split(r"\n(?=\s*(?:[-*+]|\d+\.)\s)", b) if re.match(r"\s*(?:[-*+]|\d+\.)\s", b) else [b]
            for it in items:
                kind = "li" if it is not b or re.match(r"\s*(?:[-*+]|\d+\.)\s", it) else "p"
                it = re.sub(r"^\s*(?:[-*+]|\d+\.)\s+", "", it)
                text = clean_md(it.replace("\n", " "))
                fmk = None
                if text.startswith("$$"):
                    kind = "eq"
                fmk = re.match(r"\*\*(Figure|Table) (\d+)", text)
                if fmk:
                    kind = "cap"
                if cur is None or (not text and not lead):
                    continue
                ss = [text] if kind == "eq" else sentences(text)
                cur["blocks"].append({"k": kind, **({"lead": lead} if lead else {}),
                                      **({"fig": ("fig" if fmk.group(1) == "Figure" else "tab") + fmk.group(2)} if kind == "cap" else {}),
                                      "s": [{"id": sid(cur["id"], x, seen), "t": x} for x in ss]})
                lead = None
            if lead:
                cur["blocks"].append({"k": "p", "lead": lead, "s": []})
    base = os.environ.get("BASE_LABEL") or subprocess.run(["git", "-C", str(P), "log", "-1", "--format=%h %ad", "--date=format:%Y-%m-%d %H:%M"],
                          capture_output=True, text=True).stdout.strip()
    out = {"base": base, "sections": sections}
    dest = Path(sys.argv[1]) if len(sys.argv) > 1 else P.parent / "review_text.json"
    dest.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    n = sum(len(b.get("s", [])) for s in sections for b in s["blocks"])
    print(f"{dest}: {len(sections)} sections, {n} sentences, base {base}; "
          f"largest section {max(len(json.dumps(s, ensure_ascii=False)) for s in sections) // 1024} KiB")


if __name__ == "__main__":
    main()

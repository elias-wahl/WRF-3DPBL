#!/usr/bin/env bash
# FINAL-layout render (main.tex: no line numbers, no notes, no glosses) with ONLY the changes since a git revision highlighted (Elias 2026-10-25: "only the changes of the last 72 h,
# in colour"): latexdiff of every section against BASE, additions in the review blue, deletions NOT shown (Elias 2026-10-25: "almost the final render, changes marked in colour, not what it was changed from").
# The round wrappers \rev,\revb..\revf are stripped from both sides first (latexdiff does not colour inside them).
# Usage: scripts/build_review_diff.sh [BASE]   BASE = git revision (default: last commit older than 72 h)
#        -> phd_concept/main_marked.pdf (no reMarkable push)
#        SHOW_DEL=1 scripts/build_final_marked.sh [BASE]  -> phd_concept/main_marked_del.pdf, deletions shown as small red [text]
#        (Elias 2026-10-25: "in the diff also show the things we got rid of")
set -e
C=/gpfs/data/fs72996/ewahl/concept; P=$C/phd_concept; T=/gpfs/data/fs72996/ewahl/temp/concept_marked
LD="perl $HOME/bin/latexdiff_dl/latexdiff/latexdiff-so"     # CTAN latexdiff 1.4.0, single-file version
cd $P; BASE=${1:-$(git rev-list -1 --before="72 hours ago" HEAD)}; echo "base: $(git log -1 --format='%h %ad %s' --date=short $BASE | cut -c1-90)"
rm -rf $T; mkdir -p $T/old $T/newsrc
git archive $BASE | tar -x -C $T/old
rsync -a --exclude .git --exclude '*.pdf' ./ $T/new/; cp figures/*.pdf $T/new/figures/
F="01_introduction.tex 02_state_of_research.tex 03_research_questions.tex 04_methods.tex 05_first_paper.tex 06_second_paper.tex 07_third_paper.tex 08_schedule.tex"   # 10_symbols.tex is not diffed: latexdiff breaks math inside \item[...] labels (2026-10-26); it prints uncoloured
for f in $F; do cp $f $T/newsrc/; [ -f $T/old/$f ] || touch $T/old/$f; done
python3 - $T $F <<'PY'
import re, sys, os
T = sys.argv[1]
def strip(s):
    pat = re.compile(r"\\rev[bcdefg]?\{")
    while True:
        m = pat.search(s)
        if not m: return s
        i = m.end() - 1; d = 0; k = i
        while True:
            c = s[k]
            if c == "\\": k += 2; continue
            if c == "{": d += 1
            elif c == "}":
                d -= 1
                if d == 0: break
            k += 1
        s = s[:m.start()] + s[i+1:k] + s[k+1:]
for d in ("old", "newsrc"):
    for f in sys.argv[2:]:
        p = os.path.join(T, d, f); t = strip(open(p).read()); open(p, "w").write(t)
PY
for f in $F; do $LD --config="PICTUREENV=(?:picture|DIFnomarkup|tikzpicture|ganttchart)[\w\d*@]*" --exclude-textcmd="expl,todo,open" \
    --math-markup=whole $T/old/$f $T/newsrc/$f > $T/new/$f 2>/dev/null; done
OUT=main_marked.pdf; [ "${SHOW_DEL:-0}" = 1 ] && OUT=main_marked_del.pdf
$LD --show-preamble 2>&1 | grep "%DIF PREAMBLE" \
  | sed 's|\\providecommand{\\DIFadd}\[1\]{{\\protect\\color{blue}\\uwave{#1}}}|\\providecommand{\\DIFadd}[1]{{\\protect\\color{chgcol}#1}}|' > $T/difpre.tex
python3 - $T ${SHOW_DEL:-0} <<'PY'
import sys; T, show = sys.argv[1], sys.argv[2] == "1"
dif = open(f"{T}/difpre.tex").read()
old = r"\providecommand{\DIFdel}[1]{{\protect\color{red}\sout{#1}}}"
assert old in dif, "latexdiff preamble changed"
dif = dif.replace(old, r"\providecommand{\DIFdel}[1]{{\protect\color{red!75!black}\footnotesize[#1]}}" if show else r"\providecommand{\DIFdel}[1]{}")
pre = ("\\definecolor{chgcol}{RGB}{0,84,180}\n" + dif
       + ("" if show else "\n\\renewcommand{\\DIFdel}[1]{}\\renewcommand{\\DIFdelFL}[1]{}  % deletions not shown\n"))
p = f"{T}/new/main.tex"; s = open(p).read(); s = s.replace("\\begin{document}", pre + "\\begin{document}", 1); open(p, "w").write(s)
PY
cd $T/new; source ~/miniconda3/bin/activate tex >/dev/null 2>&1 || true
tectonic --keep-intermediates main.tex >/dev/null 2>&1; ~/bin/biber main >/dev/null 2>&1; tectonic main.tex 2>&1 | grep -i -E "^error" || true
cp main.pdf $P/$OUT; pdfinfo $P/$OUT | grep Pages

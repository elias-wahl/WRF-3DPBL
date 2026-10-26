#!/usr/bin/env bash
# Review render with ONLY the changes since a git revision highlighted (Elias 2026-10-25: "only the changes of the last 72 h,
# in colour"): latexdiff of every section against BASE, additions in the review blue, deletions as small red [text].
# The round wrappers \rev,\revb..\revf are stripped from both sides first (latexdiff does not colour inside them).
# Usage: scripts/build_review_diff.sh [BASE]   BASE = git revision (default: last commit older than 72 h)
#        -> phd_concept/main_review.pdf (overwritten; no reMarkable push)
set -e
C=/gpfs/data/fs72996/ewahl/concept; P=$C/phd_concept; T=/gpfs/data/fs72996/ewahl/temp/concept_diff
LD="perl $HOME/bin/latexdiff_dl/latexdiff/latexdiff-so"     # CTAN latexdiff 1.4.0, single-file version
cd $P; BASE=${1:-$(git rev-list -1 --before="72 hours ago" HEAD)}; echo "base: $(git log -1 --format='%h %ad %s' --date=short $BASE | cut -c1-90)"
rm -rf $T; mkdir -p $T/old $T/newsrc
git archive $BASE | tar -x -C $T/old
rsync -a --exclude .git --exclude '*.pdf' ./ $T/new/; cp figures/*.pdf $T/new/figures/
F="01_introduction.tex 02_state_of_research.tex 03_research_questions.tex 04_methods.tex 05_first_paper.tex 06_second_paper.tex 07_third_paper.tex 08_schedule.tex 10_symbols.tex"
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
$LD --show-preamble 2>&1 | grep "%DIF PREAMBLE" \
  | sed 's|\\providecommand{\\DIFadd}\[1\]{{\\protect\\color{blue}\\uwave{#1}}}|\\providecommand{\\DIFadd}[1]{{\\protect\\color{chgcol}#1}}|; s|\\providecommand{\\DIFdel}\[1\]{{\\protect\\color{red}\\sout{#1}}}|\\providecommand{\\DIFdel}[1]{{\\protect\\color{red!75!black}\\footnotesize[#1]}}|' > $T/difpre.tex
python3 - $T <<'PY'
import sys; T = sys.argv[1]
pre = open(f"{T}/difpre.tex").read() + "\n\\renewcommand{\\revf}[1]{#1}\n"
p = f"{T}/new/main_review.tex"; s = open(p).read(); s = s.replace("\\begin{document}", pre + "\\begin{document}", 1); open(p, "w").write(s)
PY
cd $T/new; source ~/miniconda3/bin/activate tex >/dev/null 2>&1 || true
tectonic --keep-intermediates main_review.tex >/dev/null 2>&1; ~/bin/biber main_review >/dev/null 2>&1; tectonic main_review.tex 2>&1 | grep -i -E "^error" || true
cp main_review.pdf $P/main_review.pdf; pdfinfo $P/main_review.pdf | grep Pages

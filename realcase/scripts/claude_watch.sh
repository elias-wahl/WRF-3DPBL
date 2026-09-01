#!/bin/bash
# claude_watch.sh -- login-node crontab hook (every 15 min).
# One flag file in $DATA/.claude_wake -> one headless Claude session, strictly
# serialized by flock. Installed on Elias's explicit instruction (2026-08-31):
# "start you when needed even if the chat is closed".
DATA=/gpfs/data/fs72996/ewahl
WAKE=$DATA/.claude_wake
mkdir -p "$WAKE"
exec 9>"$WAKE/.lock"
flock -n 9 || exit 0
for f in "$WAKE"/*.txt; do
  [ -f "$f" ] || exit 0
  case "$f" in *_ok.txt|*result*) continue ;; esac   # result/status files are not instructions (2026-08-31: selftest3_ok.txt re-woke a session)
  mv "$f" "$f.handling" || continue
  cd "$DATA" || exit 1
  # Fresh session, NOT -c (Elias 2026-09-01): do not reload the previous
  # conversation's context window; the records ARE the summary. The preamble
  # forces the woken session to rebuild context from them before acting.
  PREAMBLE='AUTO-WAKE SESSION, fresh context -- deliberately started WITHOUT any previous conversation (Elias 2026-09-01: summarize from the records, do not reload old context). Before acting on the event below: (1) read the top session-end block of HANDOVER_2026-08-20.md and the newest DECISIONS.md entries; (2) write a 3-6 line summary of the project state and of what this wake-up is about as a new dated update block at the top of the handover; (3) only then diagnose/handle the event. Standing rule: record everything you find and do in the handover before ending; sync to branko/realcase/project/ and commit if git is permitted, otherwise state that the commit is pending. You run with --permission-mode acceptEdits: file edits work; git/sbatch/squeue/python may be denied -- stage commands for the next interactive session and record them instead of retrying.'
  timeout 3600 "$HOME/.npm-global/bin/claude" -p "$(printf '%s\n\n--- EVENT FLAG ---\n%s\n' "$PREAMBLE" "$(cat "$f.handling")")" \
      --permission-mode acceptEdits \
      >> "$WAKE/watch.log" 2>&1
  mv "$f.handling" "$f.done.$(date +%s)"
done

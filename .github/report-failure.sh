#!/usr/bin/env bash
# Post a failed build's compiler output back to the commit as a comment.
#
# There is no local Mac on this project, and workflow logs need an
# authenticated download. Commit comments come back through the public API, so
# this is the channel that makes a red build readable from the machine that has
# to fix it. Without it every failure costs a blind guess and another ten-minute
# round trip.
set -uo pipefail

STAGE="${1:-build}"
LOG="${2:-/tmp/build.log}"

{
  echo "**CI failure — ${STAGE}**"
  echo
  echo '```'
  if [ -f "$LOG" ]; then
    grep -E 'error:|error :|\*\* BUILD FAILED|Fatal error|fatal error' "$LOG" | head -40 \
      || echo '(no error lines matched — see tail)'
  else
    echo "(no log at $LOG)"
  fi
  echo '```'
  echo '<details><summary>tail</summary>'
  echo
  echo '```'
  [ -f "$LOG" ] && tail -70 "$LOG"
  echo '```'
  echo '</details>'
} > /tmp/comment.md

gh api "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/comments" \
  -f body="$(cat /tmp/comment.md)" --silent

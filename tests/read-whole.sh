#!/bin/bash
# The bot guard is read whole before it runs, and that is what keeps a run
# alive through an edit of its own file.
#
# bash reads a script as it executes it: after each command it reads on from
# the same byte offset, in whatever the file holds by then. Cron starts
# scripts/botguard.sh every minute, and on the server this template comes
# from a timer started a script while its file was being edited in place: a
# syntax error and a failed run. So the guard's body is one brace group,
# which bash parses in full before the first line runs, ending in exit.
#
#   the shape    the line after its header comment is "{", its last line
#                "}", the line before that an exit
#   both ways    a copy of the guard, paused inside its first docker call
#                while its own file is rewritten in place with "exit 9" at
#                the offset bash would read next: wrapped, it finishes as if
#                nothing happened; unwrapped, it runs the new text
# shellcheck disable=SC2015   # pass and fail always exit 0, so "A && pass || fail" is if-then-else here
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

echo "=== the shape ==="
echo
for f in scripts/*.sh; do
  first="$(awk 'NR > 1 && !/^#/ {print; exit}' "$f")"
  last="$(tail -1 "$f")"
  before="$(tail -2 "$f" | head -1)"
  if [ "$first" = "{" ] && [ "$last" = "}" ] && [[ $before == exit* ]] && bash -n "$f"; then
    pass "$f: one brace group, ending in \"$before\""
  else
    fail "$f: first command line \"$first\", ends \"$before\" / \"$last\""
  fi
done

echo
echo "=== both ways: the guard's own file rewritten under a running copy ==="
echo
# A copy of the guard, a config that wants no bots, and a docker that takes
# two seconds to say no server is running, so the run ends quietly, exit 0.
mkdir -p "$T/scripts" "$T/bin"
echo "bot_quota 0" >"$T/gamemode_casual_server.cfg"
printf '#!/bin/sh\nsleep 2\n' >"$T/bin/docker"
cp scripts/botguard.sh "$T/scripts/wrapped.sh"
# The same guard without its braces: what it was before.
awk -v n="$(wc -l <scripts/botguard.sh)" 'NR == n { next } !done && $0 == "{" { done = 1; next } { print }' scripts/botguard.sh >"$T/scripts/unwrapped.sh"
chmod +x "$T/bin/docker" "$T/scripts/wrapped.sh" "$T/scripts/unwrapped.sh"
grep -qx '{' "$T/scripts/unwrapped.sh" && fail "the unwrapped copy still has its brace" || true

rewritten() {  # script: run it, and rewrite its file in place while it waits
  local f="$T/scripts/$1" off
  # Just past the line that asks docker: where bash reads next.
  off="$(LC_ALL=C awk '{ off += length($0) + 1 } /^cid="\$\(docker compose/ { print off; exit }' "$f")"
  PATH="$T/bin:$PATH" bash "$f" >"$T/out" 2>&1 &
  local pid=$!
  sleep 1
  { head -c "$off" "$f"; echo 'echo "INJECTED: read from the file after it started"; exit 9'; tail -c +"$(( off + 1 ))" "$f"; } >"$T/new"
  cat "$T/new" >"$f"   # in place: same file, same inode, as an editor that saves in place
  wait "$pid"
}

rewritten wrapped.sh; rc=$?
out="$(cat "$T/out")"
[ "$rc" = 0 ] && [ -z "$out" ] && pass "wrapped: rewritten mid-run, it ran the text it started with: no server, nothing said, exit 0" \
  || fail "wrapped: exit $rc, $out"
rewritten unwrapped.sh; rc=$?
out="$(cat "$T/out")"
[ "$rc" = 9 ] && grep -q INJECTED <<<"$out" \
  && pass "unwrapped: the same rewrite, and it ran the new text, exit 9: what the braces prevent" \
  || fail "unwrapped: exit $rc, $out (the fault this guards against did not happen)"

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]

#!/bin/bash
# The bot guard and the Steam check are read whole before they run, and that
# is what keeps a run alive through an edit of its own file.
#
# bash reads a script as it executes it: after each command it reads on from
# the same byte offset, in whatever the file holds by then. Cron starts
# scripts/botguard.sh every minute and a timer starts tools/steam-uptodate.sh
# every fifteen, and on the server this template comes from a timer started a
# script while its file was being edited in place: a syntax error and a failed
# run. So each body is one brace group, which bash parses in full before the
# first line runs, ending in exit.
#
#   the shape    every scripts/*.sh and tools/*.sh: the line after its header
#                comment is "{", its last line "}", the line before that an
#                exit
#   both ways    a copy of each, paused inside its first docker call while
#                its own file is rewritten in place with "exit 9" at the
#                offset bash would read next: wrapped, it finishes as if
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
for f in scripts/*.sh tools/*.sh; do
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
echo "=== both ways: the Steam check's own file rewritten under a running copy ==="
echo
# A docker that takes two seconds to say the server is running, and Steam's
# answer supplied, so the run ends in "current".
mkdir -p "$T/tools" "$T/bin2"
printf '#!/bin/sh\nsleep 2\necho 0123456789ab\n' >"$T/bin2/docker"
printf '#!/bin/sh\necho 1.41.9.4 0 1 -\n' >"$T/bin2/probe"
cp tools/steam-uptodate.sh "$T/tools/wrapped.sh"
awk -v n="$(wc -l <tools/steam-uptodate.sh)" 'NR == n { next } !done && $0 == "{" { done = 1; next } { print }' tools/steam-uptodate.sh >"$T/tools/unwrapped.sh"
chmod +x "$T/bin2/docker" "$T/bin2/probe" "$T/tools/wrapped.sh" "$T/tools/unwrapped.sh"
grep -qx '{' "$T/tools/unwrapped.sh" && fail "the unwrapped copy still has its brace" || true

rewritten_tool() {  # script: run it, and rewrite its file in place while it waits
  local f="$T/tools/$1" off
  # The start of the line after the block that asks docker: where bash
  # reads next.
  off="$(LC_ALL=C awk '/^read -r ver humans ok req < <\(probe\)$/ { print off; exit } { off += length($0) + 1 }' "$f")"
  PATH="$T/bin2:$PATH" STEAM_UPTODATE_PROBE="$T/bin2/probe" STEAM_UPTODATE_STATE="$T/state" \
    STEAM_UPTODATE_SILENT_FILE="$T/silent" bash "$f" >"$T/out" 2>&1 &
  local pid=$!
  sleep 1
  { head -c "$off" "$f"; echo 'echo "INJECTED: read from the file after it started"; exit 9'; tail -c +"$(( off + 1 ))" "$f"; } >"$T/new"
  cat "$T/new" >"$f"
  wait "$pid"
}

rewritten_tool wrapped.sh; rc=$?
out="$(cat "$T/out")"
[ "$rc" = 0 ] && grep -q "current: version 1.41.9.4" <<<"$out" && ! grep -q INJECTED <<<"$out" \
  && pass "wrapped: rewritten mid-run, it ran the text it started with and exited 0 (${out#* * })" \
  || fail "wrapped: exit $rc, $out"
rewritten_tool unwrapped.sh; rc=$?
out="$(cat "$T/out")"
[ "$rc" = 9 ] && grep -q INJECTED <<<"$out" \
  && pass "unwrapped: the same rewrite, and it ran the new text, exit 9: what the braces prevent" \
  || fail "unwrapped: exit $rc, $out (the fault this guards against did not happen)"

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
